'use strict';

/**
 * SAFETRAILS rescue server — single binary that:
 *
 *   1. Serves the static dashboard (dashboard/) + the shared codec
 *      (shared/protocol/packet.js) over HTTP.
 *   2. Runs a WebSocket hub. Every connected dashboard becomes a peer:
 *        server -> client : {evt:'packet', packet}  |  {evt:'node_status', ...}
 *        client -> server : {cmd:'ack'|'rescue'|'broad'|'status_req', ...}
 *   3. Bridges those commands to the real rescue gateway over a serial port
 *      (SERIAL_PORT env, uses optional dep 'serialport'), OR — when no serial
 *      port is given or the module is missing — runs an embedded simulator
 *      so the full rescue flow works with zero hardware.
 *
 * The packet metric (lat/lon strings, checksum, canonical fields) is produced
 * and validated by shared/protocol/packet.js — the SAME codec the firmware,
 * the phone app, and the dashboard use.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const codec = require('../shared/protocol/packet.js');

const ROOT = __dirname;
const DASHBOARD_DIR = path.join(ROOT, '..', 'dashboard');
const SHARED_DIR = path.join(ROOT, '..', 'shared', 'protocol');
const PORT = Number(process.env.PORT || 8080);
const SERIAL_PORT = process.env.SERIAL_PORT || '';
const SERIAL_BAUD = Number(process.env.SERIAL_BAUD || 115200);

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------
const START = Date.now();
const log = (level, ...m) =>
  console.log(`${new Date().toISOString()} [${level}]`, ...m);
log('boot', `SAFETRAILS server (pid=${process.pid})`);

// ---------------------------------------------------------------------------
// HTTP static serving
// ---------------------------------------------------------------------------
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function serve(res, absPath) {
  fs.readFile(absPath, (err, buf) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('not found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(absPath)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    res.end(buf);
  });
}

function route(req, res, url) {
  if (url === '/') {
    serve(res, path.join(DASHBOARD_DIR, 'index.html'));
  } else if (url === '/shared/packet.js') {
    serve(res, path.join(SHARED_DIR, 'packet.js')); // same codec everywhere
  } else {
    // anything else maps into dashboard/
    const target = path.join(DASHBOARD_DIR, path.normalize(url).replace(/^[/\\]+/, ''));
    if (!target.startsWith(DASHBOARD_DIR)) {
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('forbidden');
      return;
    }
    serve(res, target);
  }
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  if (url === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, mode: currentMode(), uptimeSec: Math.floor((Date.now() - START) / 1000) }));
    return;
  }
  if (req.method === 'POST' && url === '/api/packet') {
    let body = '';
    req.on('data', (c) => {
      body += c;
      if (body.length > 8192) req.destroy();
    });
    req.on('end', () => {
      // Phone "Online" transport: ingest a signed SAFETRAILS packet the same
      // way the gateway's serial lines are ingested and broadcast it.
      ingestLine(body.trim(), 'online');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
    });
    req.on('error', () => {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'bad request' }));
    });
    return;
  }
  route(req, res, url);
});

// ---------------------------------------------------------------------------
// WebSocket hub
// ---------------------------------------------------------------------------
const wss = new WebSocketServer({ server });

// Bounded history so a dashboard that connects late still sees recent
// packets (the phone app sends an SOS once; if no dashboard is open at that
// instant, without replay the incident is lost). Fresh clients are sent this
// buffer right after their 'hello'.
const HISTORY_LIMIT = 256;
const history = [];

function broadcast(obj) {
  const msg = JSON.stringify(obj);
  if (obj.evt === 'packet') {
    history.push(obj);
    if (history.length > HISTORY_LIMIT) history.splice(0, history.length - HISTORY_LIMIT);
  }
  for (const client of wss.clients) {
    if (client.readyState === 1 /* OPEN */) client.send(msg);
  }
}

function sendTo(client, obj) {
  if (client.readyState === 1) client.send(JSON.stringify(obj));
}

// ---------------------------------------------------------------------------
// Transport: serial bridge (real gateway) OR simulator
// ---------------------------------------------------------------------------
let transport = null;
let transportMode = 'simulator';

// Serial bridge lifecycle (auto-reconnect).
const SERIAL_RECONNECT_MS = Number(process.env.SERIAL_RECONNECT_MS || 3000);
let serialPort = null;
let serialConnecting = false;
let serialRetryTimer = null;
let serialShutdown = false;

function currentMode() {
  return transportMode;
}

function setTransport(t, mode) {
  transport = t;
  transportMode = mode;
  log('transport', `mode=${mode}`);
}

async function loadSerialTransport() {
  let SerialPortModule = null;
  try {
    ({ SerialPort: SerialPortModule } = require('serialport'));
  } catch (e) {
    log('warn', 'serialport unavailable — falling back to simulator');
    return null;
  }

  // One attempt to open the gateway port. Resolves true when the bridge is up.
  const attempt = () => new Promise((resolve) => {
    if (serialShutdown || serialConnecting) { resolve(false); return; }
    serialConnecting = true;
    const port = new SerialPortModule({
      path: SERIAL_PORT,
      baudRate: SERIAL_BAUD,
      autoOpen: false,
    });
    port.open((err) => {
      serialConnecting = false;
      if (err) {
        log('warn', `serial open failed (${err.message})`);
        try { if (port.isOpen) port.close(); } catch (_) { /* nop */ }
        resolve(false);
        return;
      }
      serialPort = port;
      let buf = '';
      port.on('data', (chunk) => {
        buf += chunk.toString('utf8');
        let nl;
        while ((nl = buf.indexOf('\n')) >= 0) {
          const line = buf.slice(0, nl).trim();
          buf = buf.slice(nl + 1);
          if (line) ingestLine(line, 'serial');
        }
      });
      port.on('close', () => {
        log('warn', 'serial closed — reconnecting…');
        serialPort = null;
        if (!serialShutdown) scheduleSerialRetry();
      });
      port.on('error', (e) => {
        log('warn', `serial error: ${e.message}`);
        try { if (port.isOpen) port.close(); } catch (_) { /* nop */ }
      });
      setTransport({
        mode: 'serial',
        write: (obj) => {
          try {
            port.write(JSON.stringify(obj) + '\n');
          } catch (e) {
            log('warn', 'serial write failed — link reconnecting');
          }
        },
        close: () => port.close(),
      }, 'serial');
      log('transport', `serial bridge ${SERIAL_PORT} @ ${SERIAL_BAUD} (re)connected`);
      resolve(true);
    });
  });

  // Keep trying in the background if the port drops or was busy at boot.
  const scheduleSerialRetry = () => {
    if (serialShutdown || serialRetryTimer) return;
    serialRetryTimer = setTimeout(async () => {
      serialRetryTimer = null;
      const ok = await attempt();
      if (!ok && !serialShutdown) scheduleSerialRetry();
    }, SERIAL_RECONNECT_MS);
  };

  const opened = await attempt();
  if (!opened) {
    // Simulator takes over for now; we keep probing for the real gateway.
    scheduleSerialRetry();
    return null;
  }
  return transport;
}

// ---------------------------------------------------------------------------
// Inbound packet handling (simulator mode only)
// ---------------------------------------------------------------------------
let simulator = null;

function loadSimulator() {
  const { Simulator } = require('./lib/simulator.js');
  simulator = new Simulator({ codec, log, broadcast, elapsedMs: () => Date.now() - START });
  simulator.start();
  return { mode: 'simulator', write: (obj) => simulator.handleCommand(obj) };
}

// ---------------------------------------------------------------------------
// Ingest a validated packet line from either transport.
// Broadcasts it to every dashboard. In serial mode the gateway has already
// routed/ACKed; the packets shown ARE the gateway's voice.
// ---------------------------------------------------------------------------
function ingestLine(line, via) {
  if (!line) return;
  let packet;
  try {
    // Lines from serial may be a raw JSON packet OR a command envelope. Only
    // packets are ingested; envelopes are internal to the firmware.
    const parsed = JSON.parse(line);
    if (parsed.cmd) return;
    packet = codec.fromJson(line); // validates checksum + schema
  } catch (e) {
    // Some firmware lines carry a stray prefix/suffix around a valid packet
    // (log tags from a second task on the same clock tick). Rescue what we
    // can: isolate the outermost {…} and validate it before dropping the line.
    let recovered = null;
    const first = line.indexOf('{');
    const last = line.lastIndexOf('}');
    if (first >= 0 && last > first) {
      try {
        const candidate = JSON.parse(line.slice(first, last + 1));
        if (candidate && typeof candidate === 'object' && !candidate.cmd) {
          recovered = candidate;
        }
      } catch (_) { /* not a packet */ }
    }
    if (recovered) {
      packet = codec.fromJson(JSON.stringify(recovered));
    } else {
      // Meaningless line; mirror it into [rst] so NimBLE/serial debug is visible.
      const t = String(line).slice(0, 320);
      if (t) log('rst', t);
      return;
    }
  }
  log('rx', `[${via}] ${packet.type} ${packet.src}->${packet.dst} ${packet.mid} lat=${packet.lat} lon=${packet.lon}${packet.type === 'STATUS' ? ' ' + packet.body : ''}`);
    broadcast({ evt: 'packet', packet, via });
}

// ---------------------------------------------------------------------------
// Dashboard commands -> transport
// ---------------------------------------------------------------------------
function handleCommand(client, msg) {
  if (!msg || typeof msg.cmd !== 'string') return;

  switch (msg.cmd) {
    case 'ack': {
      if (!msg.mid) return sendTo(client, { evt: 'error', message: 'ack requires mid' });
      log('cmd', `ack ${msg.mid}`);
      transport.write({ cmd: 'ack', mid: String(msg.mid) });
      // Confirm to the desk straight away. The ACK packet itself may never come
      // back over serial: with the tourist's phone linked to a relay (not to
      // this gateway) the gateway forwards it over LoRa, the relay terminates it
      // locally, and nothing echoes to the PC. The operator's click is the
      // authoritative event, so reflect it instead of waiting for the wire.
      broadcast({ evt: 'message_acked', mid: String(msg.mid) });
      break;
    }
    case 'rescue': {
      if (!msg.dst) return sendTo(client, { evt: 'error', message: 'rescue requires dst' });
      log('cmd', `rescue -> ${msg.dst}`);
      transport.write({
        cmd: 'rescue', dst: String(msg.dst),
        body: String(msg.body || ''), prio: Number(msg.prio || 2),
      });
      break;
    }
    case 'broad': {
      log('cmd', `broadcast "${msg.body || ''}"`);
      transport.write({ cmd: 'broad', body: String(msg.body || ''), prio: Number(msg.prio || 3) });
      break;
    }
    case 'status_req':
      log('cmd', 'status_req');
      transport.write({ cmd: 'status_req' });
      break;
    default:
      sendTo(client, { evt: 'error', message: `unknown command ${msg.cmd}` });
  }
}

wss.on('connection', (ws) => {
  log('ws', 'dashboard connected');
  sendTo(ws, { evt: 'hello', mode: currentMode(), serverTime: Date.now() });
  for (const entry of history) {
    if (entry.evt === 'packet') sendTo(ws, entry);
  }
  ws.on('message', (raw) => {
    let msg = null;
    try {
      msg = JSON.parse(raw.toString('utf8'));
    } catch (e) {
      return sendTo(ws, { evt: 'error', message: 'bad JSON' });
    }
    handleCommand(ws, msg);
  });
});

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
async function boot() {
  let t = null;
  if (SERIAL_PORT) {
    t = await loadSerialTransport();
  }
  if (!t) t = loadSimulator();
  setTransport(t, t.mode);
  server.listen(PORT, () => {
    log('http', `dashboard on http://localhost:${PORT}/`);
    log('http', `mode: ${transportMode}${transportMode === 'serial' ? ` (${SERIAL_PORT})` : ''}`);
  });
}

boot().catch((e) => {
  console.error(e);
  process.exit(1);
});

// hitchhiker stall guard for the serial bridge
process.on('SIGINT', () => {
  serialShutdown = true;
  if (serialRetryTimer) clearTimeout(serialRetryTimer);
  if (transport && transport.close) transport.close();
  process.exit(0);
});