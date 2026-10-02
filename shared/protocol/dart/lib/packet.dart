/// SAFETRAILS shared packet codec (Dart).
///
/// Mirrors `shared/protocol/packet.js` and the ESP32 C++ codec:
/// see shared/protocol/PROTOCOL.md.
///
/// Canonical text for the checksum is identical across platforms. lat/lon are
/// kept as *verbatim strings* and normalized with [normalizeCoord] so that
/// "27.988100", 27.9881 and "27.9881" all canonicalize to 27.9881.
///
/// IMPORTANT: keep in sync with packet.js and firmware packet.cpp.
library;

import 'dart:convert';

class Packet {
  int v = 1;
  String? type;
  int prio = 0;
  String? mid;
  String? src;
  String dst = '*';
  // lat/lon stored as strings ("-" when missing) to preserve canonical text.
  String lat = noValue;
  String lon = noValue;
  int ts = 0;
  int hop = 0;
  int ttl = 8;
  int flags = 0;
  List<String> path = [];
  String ck = '';
  String body = '';

  static const String noValue = '-';
  static const int _maxCoordDecimals = 6;

  static const int flagAckRequired = 1;
  static const int flagAcked = 2;
  static const int flagRelayed = 4;
  static const int flagBroadcast = 8;

  static const List<String> kTypes = [
    'SOS', 'ACK', 'RESCUE', 'BROAD', 'STATUS', 'TRACK', 'PING', 'PONG',
  ];

  bool get isBroadcast => (flags & flagBroadcast) != 0;
  bool get ackRequired => (flags & flagAckRequired) != 0;
  bool get acked => (flags & flagAcked) != 0;
  bool get relayed => (flags & flagRelayed) != 0;

  Packet();

  factory Packet.fromJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('BAD_PACKET');
    }
    final p = Packet.fromMap(decoded);
    final recomputed = fnv1a16(canonicalFields(p));
    if (recomputed != p.ck) throw const FormatException('BAD_CHECKSUM');
    if (p.v != 1) throw const FormatException('BAD_VERSION');
    if (!kTypes.contains(p.type)) throw const FormatException('UNKNOWN_TYPE');
    if (p.mid == null || p.mid!.isEmpty || p.src == null || p.src!.isEmpty) {
      throw const FormatException('MISSING_ID');
    }
    return p;
  }

  factory Packet.fromMap(Map<String, dynamic> m) {
    final p = Packet();
    p.v = (m['v'] as num?)?.toInt() ?? 1;
    p.type = _san(m['type'], 16);
    p.prio = (m['prio'] as num?)?.toInt() ?? 0;
    p.mid = _san(m['mid'], 16, r'[^A-Za-z0-9-]');
    p.src = _san(m['src'], 16, r'[^A-Za-z0-9_-]');
    p.dst = _san(m['dst'], 16, r'[^A-Za-z0-9_*-]');
    if (p.dst.isEmpty) p.dst = '*';
    p.lat = _coordFrom(m['lat']);
    p.lon = _coordFrom(m['lon']);
    p.ts = (m['ts'] as num?)?.toInt() ?? 0;
    p.hop = ((m['hop'] as num?)?.toInt() ?? 0).clamp(0, 15);
    final ttlRaw = m['ttl'];
    p.ttl = ttlRaw == null ? 8 : ((ttlRaw as num).toInt()).clamp(0, 15);
    p.flags = ((m['flags'] as num?)?.toInt() ?? 0) & 0x0f;
    final path = m['path'];
    p.path = (path is List)
        ? path.map((e) => _san(e, 16, r'[^A-Za-z0-9_,-]')).where((x) => x.isNotEmpty).toList()
        : <String>[];
    p.ck = (m['ck'] as String?) ?? '';
    p.body = (m['body'] as String?) ?? '';
    return p;
  }

  Map<String, dynamic> toMap() {
    _normalize();
    return {
      'v': 1,
      'type': type,
      'prio': prio,
      'mid': mid,
      'src': src,
      'dst': dst,
      'lat': normalizeCoord(lat),
      'lon': normalizeCoord(lon),
      'ts': ts,
      'hop': hop,
      'ttl': ttl,
      'flags': flags,
      'path': path,
      'ck': ck,
      'body': body,
    };
  }

  String toJson() => jsonEncode(toMap());

  void _normalize() {
    mid = _san(mid, 16, r'[^A-Za-z0-9-]');
    src = _san(src, 16, r'[^A-Za-z0-9_-]');
    dst = _san(dst, 16, r'[^A-Za-z0-9_*-]');
    if (dst.isEmpty) dst = '*';
    lat = normalizeCoord(lat);
    lon = normalizeCoord(lon);
    hop = hop.clamp(0, 15);
    ttl = ttl.clamp(0, 15);
    flags &= 0x0f;
    body = body.length > 200 ? body.substring(0, 200) : body;
    ck = fnv1a16(canonicalFields(this));
  }

  /// Canonical field string over which the checksum is computed.
  static String canonicalFields(Packet p) {
    final path = p.path.isEmpty ? noValue : p.path.join(',');
    return [
      'ST', 1,
      p.type ?? '',
      p.prio,
      p.mid ?? '',
      p.src ?? '',
      p.dst,
      normalizeCoord(p.lat),
      normalizeCoord(p.lon),
      p.ts,
      p.hop,
      p.ttl,
      p.flags,
      path,
    ].join('|');
  }

  /// Encode to a compact `|`-delimited LoRa frame.
  String toCompact({int maxBody = 120}) {
    _normalize();
    String b = body.replaceAll('|', ';').replaceAll('\n', ' ').replaceAll('\r', '');
    b = b.length > maxBody ? b.substring(0, maxBody) : b;
    final frame = canonicalFields(this).split('|');
    final ckNow = fnv1a16(frame.join('|'));
    return '${frame.join('|')}|$ckNow|$b';
  }

  static Packet fromCompact(String text) {
    final f = text.split('|');
    if (f.length < 15 || f[0] != 'ST') throw const FormatException('INVALID');
    if (f[1] != '1') throw const FormatException('BAD_VERSION');
    final body = f.sublist(15).join('|');
    final frameForCk = f.sublist(0, 14).join('|');
    if (fnv1a16(frameForCk) != f[14]) throw const FormatException('BAD_CHECKSUM');
    final p = Packet()
      ..v = 1
      ..type = _san(f[2], 16)
      ..prio = int.tryParse(f[3]) ?? 0
      ..mid = f[4]
      ..src = f[5]
      ..dst = f[6]
      ..lat = f[7]
      ..lon = f[8]
      ..ts = int.tryParse(f[9]) ?? 0
      ..hop = int.tryParse(f[10]) ?? 0
      ..ttl = int.tryParse(f[11]) ?? 0
      ..flags = int.tryParse(f[12]) ?? 0
      ..path = f[13] == noValue
          ? <String>[]
          : f[13].split(',').where((x) => x.isNotEmpty).toList()
      ..ck = f[14]
      ..body = body;
    if (!kTypes.contains(p.type)) throw const FormatException('UNKNOWN_TYPE');
    if (p.mid == null || p.src == null) throw const FormatException('MISSING_ID');
    return p;
  }

  /// ASCII-only, identical-on-all-platforms lat/lon normalization.
  static String normalizeCoord(dynamic v) {
    String s;
    if (v is num) {
      s = v.toString();
    } else if (v != null) {
      s = v.toString().trim();
    } else {
      s = '';
    }
    if (s.isEmpty || s == noValue) return noValue;
    final dot = s.indexOf('.');
    if (dot < 0) return s;
    var frac = s.substring(dot + 1);
    if (frac.length > _maxCoordDecimals) frac = frac.substring(0, _maxCoordDecimals);
    frac = frac.replaceAll(RegExp(r'0+$'), '');
    if (frac.isEmpty) return s.substring(0, dot);
    return '${s.substring(0, dot)}.$frac';
  }

  static String _coordFrom(dynamic v) {
    if (v == null) return noValue;
    if (v is num) return v.toString();
    final s = v.toString();
    return (s.isEmpty || s == noValue) ? noValue : s;
  }

  /// FNV-1a 32-bit hash reduced to low 16 bits, 4 lowercase hex chars.
  static String fnv1a16(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i) & 0xff;
      h = (h * 0x01000193) & 0xffffffff;
    }
    final v = (h >> 16) & 0xffff;
    return v.toRadixString(16).padLeft(4, '0');
  }

  static String _san(String? s, int max, [String pattern = r'[|]']) {
    if (s == null) return '';
    final out = s.replaceAll(RegExp(pattern), '');
    return out.length > max ? out.substring(0, max) : out;
  }
}

/// Helpers used by the app for creating SOS / ack / track packets.
class PacketFactory {
  static int _midSeq = 0;

  static String newMid(String prefix) {
    // microsecond clock + monotonic counter + jitter so back-to-back creates
    // (and cross-platform clock resolution) never collide mids.
    final s = DateTime.now().microsecondsSinceEpoch;
    final seq = (_midSeq = (_midSeq + 1) & 0xffff);
    final jitter = s ^ (seq * 0x9E3779B1);
    return '$prefix-${jitter.toRadixString(36).toUpperCase().padLeft(8, '0')}';
  }

  static Packet sos({
    required String touristId,
    required String lat,
    required String lon,
    String? body,
    int ttl = 8,
  }) {
    return Packet()
      ..type = 'SOS'
      ..prio = 3
      ..mid = newMid('SOS')
      ..src = touristId
      ..dst = 'RCUE'
      ..lat = lat
      ..lon = lon
      ..ts = DateTime.now().millisecondsSinceEpoch ~/ 1000
      ..hop = 0
      ..ttl = ttl
      ..flags = Packet.flagAckRequired
      ..body = body ?? '';
  }

  static Packet track({
    required String touristId,
    required String lat,
    required String lon,
    int ttl = 6,
  }) {
    return Packet()
      ..type = 'TRACK'
      ..prio = 1
      ..mid = newMid('TRK')
      ..src = touristId
      ..dst = 'RCUE'
      ..lat = lat
      ..lon = lon
      ..ts = DateTime.now().millisecondsSinceEpoch ~/ 1000
      ..ttl = ttl
      ..flags = 0;
  }

  static Packet ackFor(Packet original, {String? from, int ttl = 8}) {
    return Packet()
      ..type = 'ACK'
      ..prio = original.prio
      ..mid = 'ACK-${original.mid}'
      ..src = from ?? 'RCUE'
      ..dst = original.src ?? '*'
      ..ts = DateTime.now().millisecondsSinceEpoch ~/ 1000
      ..hop = 0
      ..ttl = ttl
      ..flags = 0
      ..body = original.mid ?? '';
  }
}