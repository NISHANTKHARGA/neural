import 'package:flutter_test/flutter_test.dart';
import 'package:safetrails/link/link_controller.dart';

void main() {
  group('LinkController.parseStatusBody', () {
    test('parses live LoRa link', () {
      const body = 'node=N-A role=relay lora=1 reach=1 rssi=-68.4 snr=8.1 rx=12 '
          'loraTx=34 drop=0 seen=0 fwd=2 peers=RCUE clients=T102 uptime=1234 mem=200000';
      final h = LinkController.parseStatusBody(body);
      expect(h.loraUp, isTrue);
      expect(h.loraReach, isTrue);
      expect(h.loRaIsLive, isTrue);
      expect(h.rssiDb, -68);
      expect(h.node, 'N-A');
    });

    test('parses radio-up but unreachable', () {
      const body = 'node=N-A role=relay lora=1 reach=0 rssi=-92.0 snr=-3.5 '
          'rx=0 loraTx=12 drop=0 seen=0 fwd=0 peers=none clients=T102';
      final h = LinkController.parseStatusBody(body);
      expect(h.loraUp, isTrue);
      expect(h.loraReach, isFalse);
      expect(h.loRaIsLive, isFalse);
    });

    test('parses BLE-only relay (no LoRa)', () {
      const body = 'node=N-B role=relay lora=0 reach=0 rssi=0.0 snr=0.0 '
          'rx=0 loraTx=0 drop=0 seen=0 fwd=0 peers=none clients=T102';
      final h = LinkController.parseStatusBody(body);
      expect(h.loraUp, isFalse);
      expect(h.loRaIsLive, isFalse);
    });

    test('empty body yields inert state', () {
      final h = LinkController.parseStatusBody('');
      expect(h.loraUp, isFalse);
      expect(h.loraReach, isFalse);
      expect(h.rssiDb, isNull);
      expect(h.node, isEmpty);
    });
  });

  group('LinkTransportLabel', () {
    test('labels', () {
      expect(LinkTransport.lora.label, 'LoRa connected');
      expect(LinkTransport.ble.label, 'BLE connected');
      expect(LinkTransport.online.label, 'Online');
      expect(LinkTransport.offline.label, 'No link');
      expect(LinkTransport.lora.short, 'LoRa');
    });
  });
}