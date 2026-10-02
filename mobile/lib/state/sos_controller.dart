import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:safetrails_protocol/packet.dart';

import '../link/link_controller.dart';

enum SosState {
  created('CREATED'),
  bleSent('BLE_SENT'),
  relayed('RELAYED'),
  loraSent('LORA_SENT'),
  received('RECEIVED'),
  acknowledged('ACKNOWLEDGED'),
  onlineSent('ONLINE_SENT'),
  failed('FAILED'),
  expired('EXPIRED');

  const SosState(this.label);
  final String label;
}

class SosMessage {
  SosMessage({
    required this.packet,
    required this.status,
  });
  final Packet packet;
  SosState status;
  String? details;

  SosMessage copy() => SosMessage(packet: Packet.fromMap(packet.toMap()), status: status)
    ..details = details;
}

/// Lifecycle manager for SOS messages: create → BLE send → track delivery →
/// acknowledge. Implements retries and the CREATED…EXPIRED state machine.
class SosController extends ChangeNotifier {
  SosController({
    required this.relay,
    required this.gps,
    this.link,
  });

  final dynamic relay; // BleRelayConnection (imported lazily to keep tests light)
  final dynamic gps;
  final dynamic link; // LinkController — routes by LoRa > BLE > Online priority

  final _messages = <SosMessage>[];
  List<SosMessage> get messages => List.unmodifiable(_messages);

  SosMessage? _active;
  SosMessage? get active => _active;

  bool _sending = false;
  bool get sending => _sending;

  String? touristId = 'T102';

  StreamSubscription<dynamic>? _inboundSub;

  /// Subscribe to relay inbound stream for ACK correlation.
  void watchInbound(Stream<dynamic> inboundStream) {
    _inboundSub?.cancel();
    _inboundSub = inboundStream.listen(_onInbound);
  }

  void _onInbound(dynamic raw) {
    final Packet p = raw as Packet;
    if (p.type == 'ACK') {
      final target = _messages
          .where((m) => m.packet.mid == p.body || 'ACK-${m.packet.mid}' == p.mid)
          .toList();
      for (final m in target) {
        m.status = SosState.acknowledged;
        m.details = 'Rescue team acknowledged your SOS';
        notifyListeners();
      }
      return;
    }
    if (p.type == 'STATUS' || p.type == 'BROAD' || p.type == 'RESCUE') {
      notifyListeners(); // surfaced through AlertController too
    }
  }

  /// Full SOS flow:
  ///   1. fix GPS (satellites, no Internet)
  ///   2. build packet (unique mid, timestamp, priority, TTL)
  ///   3. connect to BLE relay
  ///   4. write SOS
  ///   5. await delivery signal / ACK
  Future<bool> sendSos({String? body}) async {
    if (_sending) return false;
    _sending = true;
    notifyListeners();

    final position = await gps.getPosition() ?? gps.last;
    final lat = position?.latitude?.toString() ?? Packet.noValue;
    final lon = position?.longitude?.toString() ?? Packet.noValue;

    final sos = PacketFactory.sos(
      touristId: touristId ?? 'T102',
      lat: lat,
      lon: lon,
      body: body,
    );
    final msg = SosMessage(packet: sos, status: SosState.created);
    _messages.insert(0, msg);
    _active = msg;
    notifyListeners();

    msg.details = 'Created (${sos.mid})';
    var sent = false;
    String? via;

    if (link != null) {
      // Transport-aware path: LoRa > BLE > Online, chosen by LinkController.
      final used = await link.sendSos(sos);
      sent = used != null;
      via = used == null ? null : (used == LinkTransport.lora ? 'lora' : used == LinkTransport.ble ? 'ble' : 'online');
      if (!sent) {
        msg.details = 'No LoRa/BLE/Online link reachable';
        notifyListeners();
      }
    } else {
      var attempts = 0;
      while (!sent && attempts < 3) {
        attempts++;
        try {
          await relay.connectAndListen().timeout(const Duration(seconds: 20));
          sent = await relay.sendSos(sos);
        } catch (_) {
          sent = false;
        }
        if (!sent) {
          msg.details = 'BLE retry $attempts/3';
          notifyListeners();
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }
    }

    if (sent) {
      _sending = false;
      if (via == 'lora') {
        msg.status = SosState.loraSent;
        msg.details = 'Sent over LoRa (relay ${link.relayNode ?? 'linked'})';
      } else if (via == 'ble') {
        msg.status = SosState.bleSent;
        msg.details = 'Sent over BLE mesh (relay ${link.relayNode ?? 'linked'})';
      } else if (via == 'online') {
        msg.status = SosState.onlineSent;
        msg.details = 'Sent over Internet (hub ${link.serverUrl})';
      } else {
        msg.status = SosState.bleSent;
        msg.details = 'Sent to relay (${sos.mid})';
      }
      notifyListeners();
      _armExpiry(msg);
      return true;
    }

    msg.status = SosState.failed;
    msg.details = 'No LoRa/BLE relay in range and no internet';
    _sending = false;
    _active = null;
    notifyListeners();
    return false;
  }

  /// Watch for the SOS to be relayed toward LoRa (mirrored by RELAYED flag
  /// or a STATUS/SOS echo from the gateway) and mark REACHED states.
  void _armExpiry(SosMessage msg) {
    Future<void>.delayed(const Duration(minutes: 5)).then((_) {
      if (msg.status == SosState.bleSent ||
          msg.status == SosState.received ||
          msg.status == SosState.loraSent) {
        msg.status = SosState.expired;
        msg.details = 'No acknowledgement received in 5 minutes';
        notifyListeners();
      }
    });
  }

  /// Called when the app learns the SOS travelled farther (e.g. "RELAYED"
  /// received from a node, or a delivery echo).
  void markRelayed(SosMessage msg) {
    if (msg.status == SosState.bleSent) {
      msg.status = SosState.relayed;
      msg.details = 'Forwarded by relay node';
      notifyListeners();
    }
  }

  void markDelivered(SosMessage msg) {
    if (msg.status == SosState.bleSent ||
        msg.status == SosState.relayed ||
        msg.status == SosState.received) {
      msg.status = SosState.received;
      msg.details = 'Received by rescue gateway';
      notifyListeners();
    }
  }

  void reset() {
    _active = null;
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _inboundSub?.cancel();
    super.dispose();
  }
}