'use strict';

/**
 * SAFETRAILS embedded network simulator (used when no serial gateway is
 * connected). Models a tourist phone, a store-and-forward relay, and the
 * rescue gateway, running the same packet codec (packet.js) and the same
 * routing lifecycle (hop/TTL/path/ACK-required) the firmware implements.
 *
 * Emits an SOS sequence a few seconds after boot so the whole flow is
 * demonstrable with no hardware at all.
 */

class Simulator {
  constructor({ codec, log, broadcast, elapsedMs }) {
    this.codec = codec;
    this.log = log;
    this.broadcast = broadcast;
    this.elapsedMs = elapsedMs;

    this.tourists = [
      { id: 'T102', lat: '27.9881', lon: '86.9250', sentiment: 'SOS' },
      { id: 'T044', lat: '27.7874', lon: '86.0986', sentiment: 'TRACK' },
    ];

    this.store = new Map(); // mid -> { packet, status, acked }
    this.seen = new Set();
    this._timers = new Set();
  }

  start() {
    // First TRACK is delayed so a freshly-connecting dashboard catches it.
    this._timers.add(setTimeout(() => this.emitTrack(), 1500));
    this._timers.add(setTimeout(() => this.emitSos(), 6000));
    this._timers.add(setInterval(() => this.emitTrack(), 20000));
    this.log('sim', 'scenario running (T102 SOS at ~6s)');
  }

  // Stop timers so a reconnected serial gateway can take over cleanly.
  stop() {
    for (const t of this._timers) {
      try { clearTimeout(t); } catch (_) { /* nop */ }
      try { clearInterval(t); } catch (_) { /* nop */ }
    }
    this._timers.clear();
    this.log('sim', 'stopped (serial gateway reconnected)');
  }

  // --- helpers -------------------------------------------------------------
  sec() {
    return Math.floor(this.elapsedMs() / 1000);
  }

  // Unique, protocol-safe message ids (A-Z0-9, may contain '-').
  newMid(prefix) {
    this._seq = (this._seq || 0) + 1;
    const t = this.sec() % 0xffff;
    const c = this._seq % 0xfff;
    return `${prefix}-${t.toString(16).toUpperCase()}${c.toString(16).toUpperCase()}`;
  }

  forward(packet, links, note) {
    // packets traverse links toward the gateway: hop++, ttl--, relayed flag,
    // path accumulated — mirroring firmware Router::process forwarding.
    for (const link of links) {
      packet.hop += 1;
      packet.ttl = Math.max(0, packet.ttl - 1);
      packet.flags |= 4; // RELAYED
      if (!packet.path.includes(link.dst)) packet.path.push(link.dst);
      this.log('sim', `  [${link.name}] -> ${link.dst} (hop=${packet.hop} ttl=${packet.ttl})`);
    }
    return packet;
  }

  // --- scenario events -------------------------------------------------------
  emitTrack() {
    const t = this.tourists[1];
    const p = this.codec.buildPacket({
      type: 'TRACK', mid: this.newMid('TRK'), prio: 1, src: t.id, dst: '*', lat: t.lat, lon: t.lon,
      ts: this.sec(), ttl: 8, body: 'trail A',
    });
    this.ship(p, [{name:'Phone-BLE', dst:'N-A'}, {name:'LoRa', dst:'RCUE'}], 'telemetry');
  }

  emitSos() {
    const t = this.tourists[0];
    const p = this.codec.buildPacket({
      type: 'SOS', mid: this.newMid('SOS'), prio: 3, src: t.id, dst: 'RCUE', lat: t.lat, lon: t.lon,
      ts: this.sec(), ttl: 8, flags: 1, // ACK_REQUIRED
      body: 'Injured on trail near Namche^Sprained ankle^Trail Sector B',
    });
    this.ship(p, [{name:'Phone-BLE', dst:'N-A'}, {name:'LoRa', dst:'RCUE'}], 'emergency');

    // Gateway auto-ACK 1.2s later, routed back toward the phone.
    setTimeout(() => {
      const ack = this.codec.buildPacket({
        type: 'ACK', prio: 3, mid: `ACK-${p.mid}`, src: 'RCUE', dst: p.src,
        ts: this.sec(), ttl: 8, body: p.mid,
      });
      this.ship(ack, [{name:'LoRa', dst:'N-A'}, {name:'Phone-BLE', dst:'T102'}], 'acknowledgement');
    }, 1200);
  }

  ship(packet, links, kind) {
    const normalized = this.codec.buildPacket(packet);
    const routed = this.forward(normalized, links, kind);
    const key = `${routed.src}:${routed.type}:${routed.mid}`;
    if (this.seen.has(key)) return; // de-dupe like the firmware SeenCache
    this.seen.add(key);
    if (kind === 'emergency' || kind === 'acknowledgement') {
      this.store.set(routed.mid, { packet: routed, status: 'RECEIVED', acked: routed.type === 'ACK' });
    }
    this.broadcast({ evt: 'packet', packet: routed, via: 'sim' });
  }

  // --- dashboard commands -----------------------------------------------------
  handleCommand(msg) {
    if (!msg || typeof msg.cmd !== 'string') return;
    switch (msg.cmd) {
      case 'ack': {
        const mid = String(msg.mid);
        const row = this.store.get(mid) || [...this.store.values()].find((r) => r.packet.mid === mid);
        if (!row) {
          this.broadcast({ evt: 'error', message: `no message ${mid} in store` });
          return;
        }
        const orig = row.packet;
        row.status = 'ACKNOWLEDGED';
        row.acked = true;
        const ack = this.codec.buildPacket({
          type: 'ACK', prio: orig.prio, mid: `ACK-${orig.mid}`, src: 'RCUE',
          dst: orig.src, ts: this.sec(), ttl: 8, body: orig.mid,
        });
        this.ship(ack, [{name:'LoRa', dst:'N-A'}, {name:'Phone-BLE', dst:'T102'}], 'acknowledgement');
        this.broadcast({ evt: 'message_acked', mid: orig.mid });
        break;
      }
      case 'rescue': {
        const p = this.codec.buildPacket({
          type: 'RESCUE', mid: this.newMid('RSC'), prio: Number(msg.prio) || 2, src: 'RCUE',
          dst: String(msg.dst), ts: this.sec(), ttl: 8,
          body: String(msg.body || 'Stay in place. Rescue launched.'),
        });
        this.ship(p, [{name:'LoRa', dst:'N-A'}, {name:'Phone-BLE', dst:'T102'}], 'rescue');
        this.store.set(p.mid, { packet: p, status: 'SENT', acked: false });
        break;
      }
      case 'broad': {
        const p = this.codec.buildPacket({
          type: 'BROAD', mid: this.newMid('BRD'), prio: Number(msg.prio) || 3, src: 'RCUE', dst: '*',
          ts: this.sec(), ttl: 12, flags: 8,
          body: `EMERGENCY^${String(msg.body || 'Heavy weather incoming')}^All trails`,
        });
        this.ship(p, [{name:'LoRa', dst:'N-A'}, {name:'Phone-BLE', dst:'T102'}], 'broadcast');
        break;
      }
      case 'status_req': {
        this.broadcast({
          evt: 'node_status',
          node: 'RCUE', role: 'gateway', uptimeSec: this.sec(),
          rx: 42, loraTx: 12, dropped: 0, seenDupes: 3, forwarded: 9,
          mem: 154312,
        });
        break;
      }
      default:
        this.broadcast({ evt: 'error', message: `cmd ${msg.cmd} not supported` });
    }
  }
}

module.exports = { Simulator };