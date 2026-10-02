import 'dart:async';

import 'package:flutter/services.dart';

import 'package:safetrails_protocol/packet.dart';

import 'ble_relay_connection.dart' show StUuids;

/// A packet received from a peer phone that wrote to our BLE GATT server.
class PeerWrite {
  const PeerWrite({required this.data, required this.charUuid});
  final String data;
  final String charUuid;

  bool get isEmergency {
    final p = charUuid.toLowerCase();
    return p == StUuids.sosTx || p == StUuids.aclTx;
  }
}

/// Thin Dart side of `SafetrailsPeripheral` (see the Kotlin source): makes the
/// phone behave as a SAFETRAILS BLE relay (GATT server + advertising) so that a
/// peer phone with no internet can hand its SOS to this phone, which forwards
/// it to the hub (and/or onward along the BLE/LoRa mesh).
class PhonePeripheral {
  static const _method = MethodChannel('safetrails/peripheral');
  static const _events = EventChannel('safetrails/peripheral/events');

  final _peerPackets = StreamController<PeerWrite>.broadcast();
  Stream<PeerWrite> get peerPackets => _peerPackets.stream;

  final _lifecycle = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get lifecycle => _lifecycle.stream;

  StreamSubscription<dynamic>? _sub;

  bool _started = false;
  bool get started => _started;

  bool _available = false;
  bool get available => _available;

  /// Kick off the event stream and verify the platform channel exists.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    _sub = _events.receiveBroadcastStream().listen((raw) {
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      final evt = (map['evt'] as String?) ?? '';
      if (evt == 'wrote') {
        _peerPackets.add(PeerWrite(
          data: (map['data'] as String?) ?? '',
          charUuid: (map['char'] as String?) ?? '',
        ));
      } else {
        _lifecycle.add(map);
      }
    }, onError: (_) {}, cancelOnError: false);
    try {
      await _method.invokeMethod<void>('noop');
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  /// Start advertising + GATT server. Returns true when the native side
  /// reported a successful start.
  Future<bool> start({String name = 'SAFETRAILS_RELAY'}) async {
    await init();
    if (!_available) return false;
    try {
      return await _method.invokeMethod<bool>('start', {'name': name}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// Notify all connected peer phones on `sosRx` / `statusRx` / `broadcastRx`
  /// / `rescueRx`. The packet JSON must be checksum-valid (the peer validates).
  Future<bool> notify(String charKey, String json) async {
    if (!_available) return false;
    try {
      return await _method.invokeMethod<bool>('notify', {'char': charKey, 'data': json}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Convenience: serialize a [Packet] (re-checksummed by [Packet.toJson]).
  Future<bool> notifyPacket(String charKey, Packet p) =>
      notify(charKey, p.toJson());

  Future<void> dispose() async {
    await _sub?.cancel();
    await _peerPackets.close();
    await _lifecycle.close();
    await stop();
  }
}