'use strict';

/**
 * SAFETRAILS rescue dashboard client.
 *
 * Two transports feed the exact same packet pipeline:
 *   - WebSocket  → Node server (which bridges a serial gateway or runs the
 *                  built-in network simulator).
 *   - Web Serial → the ESP32 rescue gateway plugged into this computer's USB
 *                  (Chrome/Edge). Raw packet JSON lines arrive on the port and
 *                  commands are written back as command envelopes.
 *
 * Everything is rendered from shared/protocol/packet.js (SafeTrails), the
 * same codec family the firmware and the phone app use.
 */

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------
const state = {
  transport: null, // {kind, send, close, online:fn}
  ws: null,
  reader: null,
  writer: null,
  port: null,
  packetByMid: new Map(),
  // mid -> { desk: bool, node: string, at: sec }. A node auto-acks the moment it
  // terminates a packet, so "ACKED" alone hides whether a human ever saw the
  // alert. Desk acks are what actually close an incident.
  ackByMid: new Map(),
  pendingDeskAck: new Set(), // mids the operator clicked ACK on
  positions: new Map(), // src -> {lat, lon, type, ts}
  serverTimeOffset: 0,
  map: null,
  mapFallback: null,   // canvas 2d context when offline
  fallbackMode: false,
  markers: new Map(),  // src -> leaflet marker
  nodes: new Set(),    // node ids that answered STATUS
  stats: { sos: 0, rescue: 0, lastRxAt: 0 },
  audio: null,         // AudioContext (created lazily after first gesture)
  soundOn: false,      // user armed the siren (also unlocks AudioContext)
  alarmUntil: 0,
  alarmTimer: null,
};

const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------------------
// logging
// ---------------------------------------------------------------------------
function log(line, cls) {
  const pre = $('log-body');
  const time = new Date().toTimeString().slice(0, 8);
  pre.textContent = `${time}  ${line}\n` + pre.textContent;
  if (pre.textContent.length > 16_000) pre.textContent = pre.textContent.slice(0, 16_000);
  if (cls) pre.className = cls;
}

// ---------------------------------------------------------------------------
// packet ingestion (shared by both transports)
// ---------------------------------------------------------------------------
function nowSec() {
  return Math.floor(Date.now() / 1000);
}

function ingestRawPacket(line, via) {
  let p;
  try {
    p = SafeTrails.fromJson(line); // validates checksum/schema
  } catch (e) {
    log(`drop [${via}] ${e.message}`, 'drop');
    return;
  }
  ingestPacket(p, via);
}

function ingestPacket(p, via) {
  const mid = p.mid;
  const prev = state.packetByMid.get(mid);
  if (!prev) {
    state.packetByMid.set(mid, { packet: p, receivedAtSec: nowSec(), via });
  } else {
    prev.packet = p; // hop/ttl/path/flags refresh as it advances
  }
  state.stats.lastRxAt = nowSec();

  // Keep track of field stations that report in for the KPI panel.
  if (p.type === 'STATUS' && p.src) state.nodes.add(p.src);
  if (p.type === 'RESCUE') state.stats.rescue++;

  // Emergencies + acks are the "incidents" table.
  if (p.type === 'SOS' || p.type === 'RESCUE' || p.type === 'BROAD' || p.type === 'ACK') {
    renderTable();
  }

  // First-ever sighting of an SOS → 5 second alarm at the rescue desk.
  if (p.type === 'SOS' && !prev) playSosAlarm();

  // Correlate ACKs back to their SOS (body carries the original mid).
  if (p.type === 'ACK') {
    const bodyMid = p.body;
    const row = state.packetByMid.get(bodyMid);
    if (row) {
      row.packet.flags |= 2; // acked locally for display
      // Distinguish a mesh node's automatic delivery receipt from the operator
      // pressing ACK at the desk: same packet shape, different meaning.
      const desk = state.pendingDeskAck.has(bodyMid);
      state.pendingDeskAck.delete(bodyMid);
      state.ackByMid.set(bodyMid, { desk, node: p.src || '?', at: nowSec() });
      renderTable();
      log(desk
        ? `desk ack ${bodyMid} (via ${p.src})`
        : `auto-ack ${bodyMid} from node ${p.src} (delivered, not confirmed by desk)`,
        'ack');
    }
  }

  // Positions (only packets with real coordinates).
  if (p.lat !== '-' && p.lon !== '-' && !isNaN(Number(p.lat)) && !isNaN(Number(p.lon))) {
    state.positions.set(p.src, { lat: Number(p.lat), lon: Number(p.lon), type: p.type, ts: p.ts });
    renderMap();
  }

  const snippet = (p.body || '').replace(/\^/g, ' — ').slice(0, 60);
  log(`[${via}] ${p.type.padEnd(4)} ${(p.src || '').padEnd(8)} -> ${(p.dst || '').padEnd(8)} ${mid}  ${snippet}`);
}

// ---------------------------------------------------------------------------
// desk alarm — 5 second siren on the first sighting of an SOS.
// ---------------------------------------------------------------------------
const ALARM_MS = 5000; // siren duration per SOS

function ensureAudio() {
  if (!state.audio) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    state.audio = new AC();
  }
  if (state.audio.state === 'suspended') {
    state.audio.resume().catch(() => {});
  }
  return state.audio;
}

function markAlarmUi(on) {
  document.body.classList.toggle('alarm', on);
}

function playSosAlarm() {
  const ctx = ensureAudio();
  const now = performance.now();
  // Any new SOS (even while one is still sounding) restarts the full window.
  state.alarmUntil = now + ALARM_MS;
  markAlarmUi(true);
  if (state.alarmTimer) return; // already sounding; window extended above
  if (!state.soundOn || !ctx || ctx.state !== 'running') {
    log('🚨 SOS received — press "Enable sound" to arm the 5s siren', 'warn');
  }
  state.alarmTimer = setInterval(() => {
    const now2 = performance.now();
    if (now2 >= state.alarmUntil) {
      clearInterval(state.alarmTimer);
      state.alarmTimer = null;
      markAlarmUi(false);
      return;
    }
    if (!ctx || ctx.state !== 'running') return; // still muted → stay silent
    // Two-tone siren: 840Hz on 0.6s / 620Hz on 0.6s.
    const remaining = state.alarmUntil - now2;
    const freq = (Math.floor(remaining / 1200) % 2 === 0) ? 840 : 620;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'square';
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, ctx.currentTime);
    gain.gain.linearRampToValueAtTime(0.12, ctx.currentTime + 0.02);
    gain.gain.setValueAtTime(0.12, ctx.currentTime + 0.5);
    gain.gain.linearRampToValueAtTime(0.0001, ctx.currentTime + 0.6);
    osc.connect(gain).connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.6);
  }, 250);
  log('🚨 SOS received — desk alarm 5s', 'warn');
}

// Browsers block audio until the first user gesture; resume once on any click.
['pointerdown', 'keydown'].forEach((ev) =>
  document.addEventListener(ev, () => ensureAudio(), { once: false }));

// Explicit "arm the siren" button — one click also unlocks the AudioContext
// (autoplay policy), so the siren fires on the next SOS even before any other
// interaction with the page.
const alarmBtn = $('alarm-btn');
if (alarmBtn) {
  const refreshAlarmBtn = () => {
    alarmBtn.textContent = state.soundOn ? '🔔 Sound ON' : '🔔 Enable sound';
    alarmBtn.dataset.on = state.soundOn ? '1' : '';
  };
  alarmBtn.addEventListener('click', () => {
    state.soundOn = true;
    refreshAlarmBtn();
    ensureAudio();
  });
  refreshAlarmBtn();
}

// ---------------------------------------------------------------------------
// table + map rendering
// ---------------------------------------------------------------------------
const FLAG_LABEL = ['ACK?', 'ACKED', 'RELAY', 'BCAST'];

function flagsText(f) {
  return ['ACK?', 'ACKED', 'RELAY', 'BCAST']
    .map((l, i) => (f & (1 << i) ? `${l}` : null))
    .filter(Boolean)
    .join(' ');
}

const BADGE = { SOS: 'badge-sos', RESCUE: 'badge-rescue', BROAD: 'badge-broad', ACK: 'badge-ack' };

function ageText(secs) {
  if (secs < 60) return `${secs}s`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m ${secs % 60}s`;
  return `${Math.floor(secs / 3600)}h`;
}

function renderTable() {
  const rows = [...state.packetByMid.values()]
    .filter((r) => ['SOS', 'RESCUE', 'BROAD'].includes(r.packet.type))
    .sort((a, b) => a.packet.ts - b.packet.ts);

  const dstOptions = new Set();
  for (const r of state.packetByMid.values()) {
    if (r.packet.type === 'SOS') dstOptions.add(r.packet.src);
  }
  const select = $('rescue-dst');
  const prevVal = select.value;
  select.innerHTML = '';
  for (const id of [...dstOptions].sort()) {
    const opt = document.createElement('option');
    opt.value = id;
    opt.textContent = id;
    if (!prevVal || prevVal === id) opt.selected = true;
    select.appendChild(opt);
  }
  if (!select.options.length) {
    const opt = document.createElement('option');
    opt.value = 'T102';
    opt.textContent = 'T102 (demo)';
    select.appendChild(opt);
  }

  // Live SOS counter on the KPI panel.
  state.stats.sos = rows.filter((r) => r.packet.type === 'SOS').length;
  renderStats();

  const tbody = $('sos-body');
  tbody.innerHTML = '';
  for (const r of rows) {
    const p = r.packet;
    const acked = !!(p.flags & 2);
    const ack = state.ackByMid.get(p.mid);
    const deskAcked = !!(ack && ack.desk);
    const ackBadge = !acked
      ? ''
      : `<span class="ack-by ${deskAcked ? 'desk' : 'auto'}" title="${
          deskAcked
            ? `confirmed by the rescue desk${ack.at ? ` · ${ageText(nowSec() - ack.at)} ago` : ''}`
            : `delivery receipt from mesh node ${esc(ack.node)} — nobody at the desk has confirmed this yet`
        }">${deskAcked ? 'desk' : `auto ${esc(ack.node)}`}</span>`;
    const tr = document.createElement('tr');
    // Only a desk ack dims the row: an auto-ack means "a node heard it", and the
    // incident is still open until a human acknowledges it.
    tr.className = `${p.type.toLowerCase()}${deskAcked ? ' acked' : ''}`;
    const age = nowSec() - (r.receivedAtSec || 0);
    tr.innerHTML =
      `<td><span class="badge ${BADGE[p.type] || ''}">${esc(p.type)}</span></td>` +
      `<td class="src">${esc(p.src)}${acked ? ' <span class="tick">✓</span>' : ''}${ackBadge}</td>` +
      `<td>${positionText(p)}</td>` +
      `<td class="flags">${flagsText(p.flags) || '<span class="dim">—</span>'}</td>` +
      `<td class="age" title="received ${age}s ago · hop ${p.hop}"><span class="age-dot"></span>${ageText(age)}</td>` +
      // Keep the button for auto-acked rows, otherwise the node's own ack would
      // remove the operator's only way to confirm the incident.
      `<td class="body">${esc(p.body || '')}${deskAcked ? '' : ackButton(p.mid)}</td>`;
    tbody.appendChild(tr);
  }
}

function ackButton(mid) {
  return `<button class="ghost" data-ack="${esc(mid)}">ACK</button>`;
}

// Coordinates for an incident. The SOS packet may lack them (no fix at that
// instant); fall back to the newest position seen for that source.
function positionText(p) {
  if (p.lat !== '-' && p.lon !== '-' && !isNaN(Number(p.lat)) && !isNaN(Number(p.lon))) {
    return `${esc(p.lat)}, ${esc(p.lon)}`;
  }
  const pos = state.positions.get(p.src);
  if (pos && !isNaN(pos.lat) && !isNaN(pos.lon)) {
    return `${pos.lat}, ${pos.lon}`;
  }
  return '-';
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

// ---- map -------------------------------------------------------------------
const NEPAL = { lat0: 26.3, lat1: 30.5, lon0: 80.0, lon1: 88.2 };

function setupMap() {
  const el = $('map');
  const fb = $('map-fallback');
  if (typeof L === 'undefined') { enableFallback(); return; }
  try {
    const m = L.map(el).setView([27.8, 85.4], 8);
    const tile = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 14,
      attribution: '&copy; OpenStreetMap',
    });
    tile.on('tileerror', () => enableFallback());
    tile.addTo(m);
    state.map = m;
    state.fallbackMode = false;
  } catch (e) {
    enableFallback();
  }
}

function enableFallback() {
  if (state.fallbackMode) return;
  state.fallbackMode = true;
  $('map').hidden = true;
  $('map-fallback').hidden = false;
  state.mapFallback = $('map-canvas').getContext('2d');
  renderMap();
}

function project(lat, lon) {
  const { lat0, lat1, lon0, lon1 } = NEPAL;
  const x = ((lon - lon0) / (lon1 - lon0)) * 900;
  const y = 480 - ((lat - lat0) / (lat1 - lat0)) * 480;
  return [x, y];
}

function renderMap() {
  if (state.fallbackMode) {
    const ctx = state.mapFallback;
    ctx.clearRect(0, 0, 900, 480);
    ctx.strokeStyle = '#2b4150';
    ctx.strokeRect(10, 10, 880, 460);
    ctx.fillStyle = '#3ecf8e';
    ctx.font = '12px monospace';
    ctx.fillText('SAFETRAILS · offline projection (26.3–30.5°N / 80–88.2°E)', 20, 24);
    for (const [src, pos] of state.positions) {
      const [x, y] = project(pos.lat, pos.lon);
      ctx.beginPath();
      ctx.arc(x, y, pos.type === 'SOS' ? 9 : 6, 0, Math.PI * 2);
      ctx.fillStyle = pos.type === 'SOS' ? '#ff5d5d' : pos.type === 'TRACK' ? '#3ecf8e' : '#ffc857';
      ctx.fill();
      ctx.strokeStyle = '#dbe6ee';
      ctx.stroke();
      ctx.fillStyle = '#dbe6ee';
      ctx.fillText(src + (pos.type === 'SOS' ? ' ●' : ''), x + 10, y - 6);
    }
    return;
  }
  if (!state.map) return;
  for (const [src, pos] of state.positions) {
    const existing = state.markers.get(src);
    const color = pos.type === 'SOS' ? '#ff5d5d' : pos.type === 'TRACK' ? '#3ecf8e' : '#ffc857';
    if (existing) {
      existing.setLatLng([pos.lat, pos.lon]);
      existing.setStyle({ color });
      existing.setPopupContent(`${src} · ${pos.type} · ${pos.lat}, ${pos.lon}`);
    } else {
      const mk = L.circleMarker([pos.lat, pos.lon], {
        radius: pos.type === 'SOS' ? 10 : 6, color, fillColor: color, fillOpacity: 0.7,
      }).addTo(state.map);
      mk.bindPopup(`${src} · ${pos.type} · ${pos.lat}, ${pos.lon}`);
      state.markers.set(src, mk);
    }
  }
}

// ---------------------------------------------------------------------------
// transports
// ---------------------------------------------------------------------------

function connectWs() {
  const proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
  // The gateway embedded hub serves the page on :80 but its WebSocket lives
  // on :81 (Node server serves both on the same port). Pick the right one.
  const wsPort = (!location.port || location.port === '80') ? ':81' : ':' + location.port;
  const ws = new WebSocket(proto + location.hostname + wsPort);
  state.transport = { kind: 'ws', send: (o) => ws.readyState === 1 && ws.send(JSON.stringify(o)) };
  state.ws = ws;
  ws.onopen = () => {
    setConn(true, 'ws connected');
    log('transport: websocket open');
  };
  ws.onmessage = (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    if (msg.evt === 'hello') {
      log(`hello: server mode = ${msg.mode}`);
      return;
    }
    if (msg.evt === 'packet') ingestPacket(msg.packet, msg.via || 'ws');
    else if (msg.evt === 'node_status') renderNodeStatus(msg);
    else if (msg.evt === 'message_acked') {
      const row = state.packetByMid.get(msg.mid);
      if (row) {
        row.packet.flags |= 2;
        state.pendingDeskAck.delete(msg.mid);
        state.ackByMid.set(msg.mid, { desk: true, node: 'desk', at: nowSec() });
        renderTable();
        log(`server confirms desk ack ${msg.mid}`, 'ack');
      }
    } else if (msg.evt === 'error') {
      log(`server: ${msg.message}`, 'drop');
    }
  };
  ws.onclose = () => {
    setConn(false, 'ws closed');
    if (state.transport && state.transport.kind === 'ws') state.transport = null;
    if ($('mode').value === 'ws') {
      // Auto-reconnect so the rescue desk never needs to press Connect by hand.
      setTimeout(connectWs, 3000);
    }
  };
  ws.onerror = () => { setConn(false, 'ws reconnecting…'); };
}

async function connectSerial() {
  if (!navigator.serial) {
    log('Web Serial unavailable — use Chrome/Edge, or the WebSocket mode', 'warn');
    return;
  }
  try {
    const port = await navigator.serial.requestPort();
    await port.open({ baudRate: 115200 });
    state.port = port;
    state.reader = port.readable.getReader();
    state.writer = port.writable.getWriter();

    state.transport = {
      kind: 'serial',
      send: (o) => state.writer && state.writer.write(new TextEncoder().encode(JSON.stringify(o) + '\n')),
    };
    setConn(true, 'serial connected');

    let buf = '';
    const readLoop = async () => {
      try {
        while (true) {
          const { value, done } = await state.reader.read();
          if (done) break;
          buf += new TextDecoder().decode(value);
          let nl;
          while ((nl = buf.indexOf('\n')) >= 0) {
            const line = buf.slice(0, nl).trim();
            buf = buf.slice(nl + 1);
            if (!line || line.startsWith('[')) continue; // skip firmware banners/braces
            if (!line.startsWith('{')) continue;
            try {
              if (JSON.parse(line).cmd) continue; // command envelope, not a packet
            } catch (e) { continue; }
            ingestRawPacket(line, 'serial');
          }
        }
      } catch (e) {
        log('serial read ended');
      }
    };
    readLoop();
  } catch (e) {
    log(`serial connect failed: ${e.message || e}`, 'warn');
  }
}

function sendCommand(cmd, extra) {
  if (!state.transport) { log('not connected', 'warn'); return; }
  state.transport.send(Object.assign({ cmd }, extra));
}

function setConn(on, label) {
  const el = $('conn-state');
  el.className = 'state ' + (on ? 'on' : 'off');
  el.textContent = label || (on ? 'connected' : 'disconnected');
}

// ---------------------------------------------------------------------------
// ui wiring
// ---------------------------------------------------------------------------
$('connect').addEventListener('click', () => {
  if ($('mode').value === 'ws') return; // ws auto-connects; button is for serial
  connectSerial();
});

function setModeUi() {
  const isWs = $('mode').value === 'ws';
  $('connect').disabled = isWs;
  $('connect').textContent = isWs ? 'auto' : 'Connect';
  if (isWs && !state.transport) connectWs();
}

$('mode').addEventListener('change', setModeUi);

$('sos-body').addEventListener('click', (e) => {
  const btn = e.target.closest('[data-ack]');
  if (btn) {
    // Remember the intent: the ACK packet that comes back is indistinguishable
    // from the node's own auto-ack, so the dashboard has to know we asked.
    state.pendingDeskAck.add(btn.dataset.ack);
    sendCommand('ack', { mid: btn.dataset.ack });
  }
});

$('btn-rescue').addEventListener('click', () => {
  sendCommand('rescue', { dst: $('rescue-dst').value, body: $('rescue-body').value, prio: 2 });
});

$('btn-broad').addEventListener('click', () => {
  sendCommand('broad', { body: $('broad-body').value, prio: 3 });
});

$('btn-status').addEventListener('click', () => sendCommand('status_req'));

function renderNodeStatus(s) {
  $('node-status').textContent =
    `${s.node} · ${s.role}\n` +
    `uptime ${s.uptimeSec}s · rx ${s.rx} · loraTx ${s.loraTx} · dropped ${s.dropped}\n` +
    `seenDupes ${s.seenDupes} · forwarded ${s.forwarded} · mem ${s.mem}B`;
}

// ---------------------------------------------------------------------------
// KPI panel + live clock
// ---------------------------------------------------------------------------
function renderStats() {
  $('stat-sos').textContent = state.stats.sos;
  $('stat-nodes').textContent = state.nodes.size ? state.nodes.size : '—';
  $('stat-rescue').textContent = state.stats.rescue;

  let lastFix = '—';
  let newestTs = 0;
  for (const pos of state.positions.values()) {
    const t = pos.ts || 0;
    if (t > newestTs) { newestTs = t; lastFix = `${pos.lat.toFixed(4)}, ${pos.lon.toFixed(4)}`; }
  }
  const since = newestTs ? nowSec() - newestTs : null;
  $('stat-fix').textContent = since === null ? lastFix : since <= 5 ? lastFix : `${Math.trunc(since / 60)}m`;
  $('stat-fix').title = lastFix;

  const link = state.transport ? state.transport.kind : 'idle';
  const idle = state.stats.lastRxAt ? `last packet ${nowSec() - state.stats.lastRxAt}s ago` : 'no traffic yet';
  $('foot-live').textContent = `link: ${link} · ${idle}`;
}

// Keep ages ticking and the KPI panel honest while the desk is open.
setInterval(renderStats, 1000);

// start
setupMap();
renderTable();
renderStats();
setModeUi();
log('dashboard ready — websocket connecting automatically…');