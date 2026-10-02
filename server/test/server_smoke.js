'use strict';

/**
 * SAFETRAILS server smoke test — runs index.js headlessly, connects a WS
 * dashboard, and asserts the full emergency flow observed end-to-end:
 * TRACK -> SOS -> gateway ACK, then a RESCUE + manual ACK round-trip.
 *
 * Run:  node test/server_smoke.js   (from server/)
 */

const { spawn } = require('child_process');
const http = require('http');
const path = require('path');
const WebSocket = require('ws');

const PORT = Number(process.env.TEST_PORT || 9731 + (process.pid % 97));
const BASE = `http://127.0.0.1:${PORT}`;

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitHealth(timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const status = await new Promise((resolve, reject) => {
        const req = http.get(`${BASE}/api/health`, (res) => {
          res.resume();
          resolve(res.statusCode);
        });
        req.on('error', reject);
      });
      if (status === 200) return;
    } catch (e) { /* not up yet */ }
    await wait(200);
  }
  throw new Error('server did not become healthy in time');
}

(async () => {
  const child = spawn(process.execPath, ['index.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let serverLog = '';
  child.stdout.on('data', (d) => { serverLog += d.toString(); });
  child.stderr.on('data', (d) => { serverLog += d.toString(); });
  const killChild = () => { try { child.kill('SIGKILL'); } catch (e) { /* gone */ } };
  process.on('exit', killChild);

  const seen = { track: false, sos: false, autoAck: false, rescue: false, manualAck: false };
  let sosMid = null;
  let failures = 0;

  try {
    await waitHealth(12000);

    const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
    const events = [];
    ws.on('message', (raw) => events.push(JSON.parse(raw.toString())));

    await new Promise((resolveOpen, rejectOpen) => {
      ws.on('open', () => {
        // send a manual RESCUE before the auto-SOS lands
        ws.send(JSON.stringify({ cmd: 'rescue', dst: 'T102', body: 'Stay put', prio: 2 }));
        resolveOpen();
      });
      ws.on('error', rejectOpen);
    });
    ws.on('error', () => { /* keep reading window alive */ });

    const deadline = Date.now() + 16000;
    let manualAckSent = false;
    while (Date.now() < deadline) {
      for (const ev of events.splice(0)) {
        if (ev.evt === 'packet' && ev.packet) {
          const p = ev.packet;
          if (p.type === 'TRACK') seen.track = true;
          if (p.type === 'SOS') { seen.sos = true; sosMid = p.mid; }
          if (p.type === 'RESCUE') seen.rescue = true;
          // Gateway auto-ACK for the SOS, then we manually ACK it too.
          if (p.type === 'ACK' && p.body === sosMid && sosMid) {
            seen.autoAck = true;
            if (!manualAckSent) {
              manualAckSent = true;
              ws.send(JSON.stringify({ cmd: 'ack', mid: sosMid }));
            }
          }
        }
        if (ev.evt === 'message_acked' && ev.mid === sosMid) seen.manualAck = true;
      }
      if (seen.track && seen.sos && seen.autoAck && seen.rescue && seen.manualAck) break;
      await wait(250);
    }

    // Ask for a node status snapshot.
    ws.send(JSON.stringify({ cmd: 'status_req' }));
    await wait(400);

    // Drain any final events.
    for (const ev of events.splice(0)) {
      if (ev.evt === 'node_status' && ev.node === 'RCUE') seen.statusReq = true;
      if (ev.evt === 'packet' && ev.packet) {
        const p = ev.packet;
        if (p.type === 'TRACK') seen.track = true;
        if (p.type === 'SOS') { seen.sos = true; sosMid = p.mid; }
        if (p.type === 'RESCUE') seen.rescue = true;
        if (p.type === 'ACK' && p.body === sosMid && sosMid) seen.autoAck = true;
      }
      if (ev.evt === 'message_acked' && ev.mid === sosMid) seen.manualAck = true;
    }

    console.log('seen:', JSON.stringify(seen));
    for (const [k, v] of Object.entries(seen)) {
      if (!v) { failures += 1; console.log(`  FAIL ${k}`); }
    }
    ws.close();
  } catch (e) {
    console.error('smoke test error:', e.message);
    console.error('--- server output ---');
    console.error(serverLog.split('\n').slice(0, 25).join('\n') || '(no output)');
    console.error('--------------------');
    failures += 1;
  } finally {
    killChild();
  }

  setImmediate(() => {
    console.log(failures ? `smoke test FAILED (${failures})` : 'smoke test OK');
    process.exit(failures ? 1 : 0);
  });
})();

process.on('unhandledRejection', (e) => {
  console.error(e);
  process.exit(2);
});