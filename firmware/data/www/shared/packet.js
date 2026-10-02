'use strict';

/**
 * SAFETRAILS shared packet codec (JavaScript).
 * See shared/protocol/PROTOCOL.md
 *
 * Two encodings of one logical packet:
 *   - JSON: BLE + serial + WebSocket
 *   - Compact: LoRa radio frames
 *
 * lat/lon are kept as verbatim strings and canonicalized with normalizeCoord,
 * so checksums are byte-identical across JS / Dart / C++.
 *
 * Used by both the dashboard (browser) and the Node server.
 */

const TYPES = ['SOS', 'ACK', 'RESCUE', 'BROAD', 'STATUS', 'TRACK', 'PING', 'PONG'];

const FLAG_ACK_REQUIRED = 1;
const FLAG_ACKED = 2;
const FLAG_RELAYED = 4;
const FLAG_BROADCAST = 8;

const NO_VALUE = '-';
const MAX_COORD_DECIMALS = 6;
const MAX_BODY_COMPACT = 120;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function fnv1a16(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i) & 0xff;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  const v = (h >>> 16) & 0xffff;
  return v.toString(16).padStart(4, '0').toLowerCase();
}

/** ASCII-only, identical-on-all-platforms lat/lon normalization. */
function normalizeCoord(v) {
  let s;
  if (v === undefined || v === null) s = '';
  else if (typeof v === 'number') s = String(v);
  else s = String(v).trim();
  if (s === '' || s === NO_VALUE) return NO_VALUE;
  const dot = s.indexOf('.');
  if (dot < 0) return s;
  let frac = s.slice(dot + 1);
  if (frac.length > MAX_COORD_DECIMALS) frac = frac.slice(0, MAX_COORD_DECIMALS);
  frac = frac.replace(/0+$/, '');
  if (frac === '') return s.slice(0, dot);
  return `${s.slice(0, dot)}.${frac}`;
}

function coordFrom(v) {
  if (v === undefined || v === null) return NO_VALUE;
  if (typeof v === 'number') return String(v);
  const s = String(v);
  return s === '' || s === NO_VALUE ? NO_VALUE : s;
}

function sanitizeToken(s, max, pattern) {
  if (s === undefined || s === null) return '';
  const out = String(s).replace(new RegExp(pattern, 'g'), '');
  return out.length > max ? out.slice(0, max) : out;
}

function sanitizeBody(s) {
  // '|' is a frame delimiter on LoRa → encoded as ';'. Newlines stripped.
  if (s === undefined || s === null) return '';
  return String(s).replace(/[|]/g, ';').replace(/[\n\r]+/g, '').slice(0, MAX_BODY_COMPACT);
}

// Canonical field string used for the checksum (delimiter `|`, gaps marked `-`).
function canonicalFields(p) {
  const path = Array.isArray(p.path) && p.path.length ? p.path.join(',') : NO_VALUE;
  return [
    'ST', 1,
    p.type || '',
    p.prio === undefined || p.prio === null ? 0 : p.prio,
    p.mid || '',
    p.src || '',
    p.dst || '*',
    normalizeCoord(p.lat),
    normalizeCoord(p.lon),
    p.ts === undefined ? 0 : p.ts,
    p.hop === undefined ? 0 : p.hop,
    p.ttl === undefined ? 0 : p.ttl,
    p.flags === undefined ? 0 : p.flags,
    path,
  ].join('|');
}

function defaults() {
  return {
    v: 1, type: null, prio: 0, mid: null, src: null, dst: '*',
    lat: NO_VALUE, lon: NO_VALUE, ts: 0, hop: 0, ttl: 8, flags: 0,
    path: [], ck: '', body: '',
  };
}

// ---------------------------------------------------------------------------
// JSON codec
// ---------------------------------------------------------------------------

/** Build a fresh packet object ready for sending (normalises + checksums). */
function buildPacket(input) {
  const p = Object.assign(defaults(), input || {});
  p.v = 1;
  p.type = String(p.type || 'SOS');
  p.mid = sanitizeToken(p.mid, 16, '[^A-Za-z0-9-]');
  p.src = sanitizeToken(p.src, 16, '[^A-Za-z0-9_-]');
  const dst = sanitizeToken(p.dst, 16, '[^A-Za-z0-9_*-]');
  p.dst = dst || '*';
  const lat = coordFrom(p.lat);
  const lon = coordFrom(p.lon);
  p.lat = normalizeCoord(lat);
  p.lon = normalizeCoord(lon);
  p.hop = Math.max(0, Math.floor(Number(p.hop) || 0));
  const ttlRaw = p.ttl === undefined || p.ttl === null ? 8 : p.ttl;
  const ttlNum = Number(ttlRaw);
  p.ttl = Number.isFinite(ttlNum) ? Math.max(0, Math.floor(ttlNum)) : 8;
  p.flags = Math.floor(Number(p.flags) || 0) & 0x0f;
  if (!Array.isArray(p.path)) p.path = [];
  p.path = p.path
    .map((x) => sanitizeToken(x, 16, '[^A-Za-z0-9_,-]'))
    .filter((x) => x.length);
  p.body = sanitizeToken(p.body, 200, '[\\n\\r]');
  p.ck = fnv1a16(canonicalFields(p));
  return p;
}

/** Serialise a logical packet to its canonical JSON string. */
function toJson(p) {
  return JSON.stringify(buildPacket(p));
}

/** Parse and validate a JSON packet string. Throws on invalid input. */
function fromJson(text) {
  const parsed = JSON.parse(text);
  const p = buildPacket(parsed);
  if (p.ck !== (parsed.ck || '')) throw new Error('BAD_CHECKSUM');
  if (p.v !== 1) throw new Error('BAD_VERSION');
  if (!TYPES.includes(p.type)) throw new Error('UNKNOWN_TYPE');
  if (!p.mid || !p.src) throw new Error('MISSING_ID');
  return p;
}

// ---------------------------------------------------------------------------
// Compact (LoRa) codec
// ---------------------------------------------------------------------------

/** Encode a logical packet into a compact `|`-delimited LoRa frame. */
function toCompact(p, opts) {
  const o = opts || {};
  const n = buildPacket(p);
  const maxBody = o.maxBody === undefined ? MAX_BODY_COMPACT : o.maxBody;
  let body = sanitizeBody(n.body);
  body = body.length > maxBody ? body.slice(0, maxBody) : body;
  const frame = canonicalFields(n).split('|');
  const ck = fnv1a16(frame.join('|'));
  return `${frame.join('|')}|${ck}|${body}`;
}

/** Decode a compact frame. Throws on invalid/malformed/checksum-failed input. */
function fromCompact(text) {
  if (typeof text !== 'string') throw new Error('INVALID');
  const f = text.split('|');
  if (f.length < 15 || f[0] !== 'ST') throw new Error('INVALID');
  if (f[1] !== '1') throw new Error('BAD_VERSION');
  const body = f.slice(15).join('|');
  const frameForCk = f.slice(0, 14).join('|');
  if (fnv1a16(frameForCk) !== f[14]) throw new Error('BAD_CHECKSUM');
  const p = defaults();
  p.type = f[2];
  p.prio = Number(f[3]);
  p.mid = f[4];
  p.src = f[5];
  p.dst = f[6];
  p.lat = f[7];
  p.lon = f[8];
  p.ts = Number(f[9]);
  p.hop = Number(f[10]);
  p.ttl = Number(f[11]);
  p.flags = Number(f[12]);
  p.path = f[13] === NO_VALUE ? [] : f[13].split(',').filter((x) => x.length);
  p.ck = f[14];
  p.body = body;
  if (!TYPES.includes(p.type)) throw new Error('UNKNOWN_TYPE');
  if (!p.mid || !p.src) throw new Error('MISSING_ID');
  return p;
}

// ---------------------------------------------------------------------------

const packet = {
  buildPacket, toJson, fromJson, toCompact, fromCompact,
  fnv1a16, canonicalFields, normalizeCoord,
  FLAG_ACK_REQUIRED, FLAG_ACKED, FLAG_RELAYED, FLAG_BROADCAST, TYPES,
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = packet;
} else {
  window.SafeTrails = packet;
}