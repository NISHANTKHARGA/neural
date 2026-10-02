import 'package:flutter_test/flutter_test.dart';
import 'package:safetrails_protocol/packet.dart';

void main() {
  group('Packet codec', () {
    test('SOS factory builds a valid, checksummed packet', () {
      final p = PacketFactory.sos(
        touristId: 'T102',
        lat: '27.9881',
        lon: '86.9250',
        body: 'I need emergency assistance',
      );
      expect(p.type, 'SOS');
      expect(p.prio, 3);
      expect(p.mid, startsWith('SOS-'));
      expect(p.src, 'T102');
      expect(p.dst, 'RCUE');
      expect(p.ackRequired, isTrue);

      // toMap -> fromJson round trip validates checksum
      p.toJson(); // computes ck via _normalize()
      expect(p.ck, isNotEmpty);
      expect(p.toJson(), contains(p.ck));
      final p2 = Packet.fromJson(p.toJson());
      expect(p2.mid, p.mid);
    });

    test('compact (LoRa) and JSON round-trip are equivalent', () {
      final p = PacketFactory.sos(
        touristId: 'T102',
        lat: '27.9881',
        lon: '86.925',
        body: 'I need emergency assistance',
      );
      final compact = p.toCompact();
      expect(compact, startsWith('ST|1|SOS|3|'));
      final fromCompact = Packet.fromCompact(compact);
      expect(fromCompact.mid, p.mid);
      expect(fromCompact.lat, '27.9881');
      expect(fromCompact.lon, '86.925');
      expect(fromCompact.body, p.body);
    });

    test('tampered frame is rejected (checksum)', () {
      final p = PacketFactory.sos(touristId: 'T102', lat: '1.0', lon: '2.0');
      final compact = p.toCompact();
      final parts = compact.split('|');
      parts[4] = 'HAXXOR'; // mid
      final tampered = parts.join('|');
      expect(() => Packet.fromCompact(tampered), throwsFormatException);
    });

    test('malformed frames are rejected', () {
      expect(() => Packet.fromCompact('junk'), throwsFormatException);
      expect(() => Packet.fromCompact('ST|1|SOS|too-short'), throwsFormatException);
    });

    test('duplicate suppression uses src:type:mid', () {
      final a = PacketFactory.sos(touristId: 'T102', lat: '1.0', lon: '2.0');
      final b = PacketFactory.sos(touristId: 'T102', lat: '3.0', lon: '4.0');
      expect(a.mid, isNot(b.mid));
    });
  });
}