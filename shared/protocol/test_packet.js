'use strict';
// SAFETRAILS shared codec self-test — run: node shared/protocol/test_packet.js
const assert = require('assert');
const p = require('./packet.js');

// 1) Cross-platform vector: this exact frame must parse in Dart and C++ too.
const FRAME =
  'ST|1|SOS|3|SOS-8F23A91|T102|RCUE|27.9881|86.925|1770000000|0|8|3|RCUE|' +
  'eab3|I need emergency assistance';

assert.strictEqual(
  p.toCompact(p.buildPacket({
    type: 'SOS', prio: 3, mid: 'SOS-8F23A91', src: 'T102', dst: 'RCUE',
    lat: '27.988100', lon: '86.925000', ts: 1770000000, hop: 0, ttl: 8,
    flags: 3, path: ['RCUE'], body: 'I need emergency assistance',
  })), FRAME, 'toCompact must produce the reference frame');

const parsed = p.fromCompact(FRAME);
assert.strictEqual(parsed.mid, 'SOS-8F23A91');
assert.strictEqual(parsed.lat, '27.9881');
assert.strictEqual(parsed.dst, 'RCUE');
assert.strictEqual(parsed.path.join(','), 'RCUE');
assert.strictEqual(p.toCompact(parsed), FRAME, 'round-trip must be stable');

// 2) JSON round-trip keeps checksum amid unnormalized coordinates.
const jsonStr = JSON.stringify({
  v: 1, type: 'SOS', prio: 0, mid: 'SOS-8F23A91', src: 'T102', dst: 'RCUE',
  lat: '27.988100', lon: '86.925000', ts: 1770000000, hop: 0, ttl: 8, flags: 3,
  path: ['RCUE'], ck: '4e17', body: 'I need emergency assistance',
});
const fromJ = p.fromJson(jsonStr);
assert.strictEqual(fromJ.lat, '27.9881');
assert.strictEqual(fromJ.ck, '4e17');

// 3) Tampering a checksum-covered field must fail.
assert.throws(
  () => p.fromCompact(FRAME.replace('SOS-8F23A91', 'SOS-8F23A99')),
  /BAD_CHECKSUM/);
assert.throws(() => p.fromCompact('junk|data'), /INVALID/);
// Changing the type also alters covered fields → BAD_CHECKSUM fires first.
assert.throws(() => p.fromCompact(FRAME.replace(/\|SOS\|/, '|SOC|')));

// 4) Body pipe-encoding matches C++/Dart ('|' -> ';').
const san = p.toCompact(p.buildPacket({
  type: 'RESCUE', mid: 'RSC-B', src: 'RCUE', dst: 'T102', ts: 1770000300,
  ttl: 8, body: 'A|B||C',
}));
assert.ok(san.endsWith('A;B;;C'), 'each pipe becomes a semicolon, got ' + san);

console.log('test_packet.js OK');