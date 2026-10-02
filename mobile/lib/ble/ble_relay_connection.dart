import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:safetrails_protocol/packet.dart';

/// Adapter UUIDs — see shared/protocol/PROTOCOL.md §3.
abstract final class StUuids {
  static const service = '2f32f800-6a00-4f6a-9a5e-001122334455';
  static const sosTx = '2f32f801-6a00-4f6a-9a5e-001122334455';
  static const sosRx = '2f32f802-6a00-4f6a-9a5e-001122334455';
  static const aclTx = '2f32f803-6a00-4f6a-9a5e-001122334455';
  static const rescueRx = '2f32f804-6a00-4f6a-9a5e-001122334455';
  static const broadcastRx = '2f32f805-6a00-4f6a-9a5e-001122334455';
  static const statusRx = '2f32f806-6a00-4f6a-9a5e-001122334455';
  static const dataRx = '2f32f807-6a00-4f6a-9a5e-001122334455';

  static const advertiseName = 'SAFETRAILS_RELAY';
}

enum BleLinkState { off, scanning, connecting, connected, error }

/// Manages the phone ⇆ SAFETRAILS relay BLE (GATT) link.
///
/// - scans for relays advertising as SAFETRAILS_RELAY
/// - connects, subscribes to notify characteristics
/// - sends SOS / ack JSON packets
/// - surfaces inbound packets + relay status as streams
class BleRelayConnection {
  BleRelayConnection();

  final _stateController = ValueNotifier<BleLinkState>(BleLinkState.off);
  ValueNotifier<BleLinkState> get state => _stateController;

  final _errorController = ValueNotifier<String?>(null);
  ValueNotifier<String?> get error => _errorController;

  void reportError(String msg) {
    _stateController.value = BleLinkState.error;
    _errorController.value = msg;
  }

  final _inbound = StreamController<Packet>.broadcast();
  Stream<Packet> get packets => _inbound.stream;

  final _nodeStatus = StreamController<String>.broadcast();
  Stream<String> get nodeStatus => _nodeStatus.stream;

  // Diagnostics: characteristics the node does not expose, and frames the app
  // itself refused to parse. Both used to vanish silently, which made a
  // "nothing arrives" fault impossible to place on the radio vs the app.
  final List<String> _missingChars = <String>[];
  List<String> get missingCharacteristics => List.unmodifiable(_missingChars);

  final _rssi = ValueNotifier<int?>(null);
  ValueNotifier<int?> get rssi => _rssi;

  BluetoothDevice? _device;
  List<StreamSubscription<dynamic>> _subs = [];
  Timer? _rssiTicker;
  bool _receiving = false;

  /// BLE address of the node we are linked to, so the caller can blacklist a
  /// node it has decided not to use (see LinkController.forceRelayHop).
  String? get connectedDeviceId => _device?.remoteId.str;

  /// Debug hook fired once per ScanResult while scanning: lets the UI show
  /// whether peer phones are even being seen by the radio.
  void Function(String description, bool isSafetrails)? onScanSeen;

  bool get isConnected => _device != null && !_receiving;

  Future<bool> ensurePermissions() async {
    var ok = true;
    // Android <=11 requires location for BLE scanning (and it's harmless to
    // hold on newer versions). Request it if not yet decided.
    final loc = await Permission.locationWhenInUse.status;
    if (loc.isDenied || loc.isRestricted) {
      final geo = await Permission.locationWhenInUse.request();
      if (geo.isGranted || geo.isLimited) ok = true; else ok = false;
    } else if (loc.isPermanentlyDenied) {
      ok = false;
    }
    // Prefer the modern "Nearby devices" permission on Android >=12; request
    // it whenever it isn't granted yet so the OS dialog actually appears.
    final scan = await Permission.bluetoothScan.status;
    if (scan.isDenied || scan.isRestricted) {
      final b = await Permission.bluetoothScan.request();
      if (!b.isGranted) ok = false;
    } else if (scan.isPermanentlyDenied) {
      ok = false;
    }
    final connect = await Permission.bluetoothConnect.status;
    if (connect.isDenied || connect.isRestricted) {
      final c = await Permission.bluetoothConnect.request();
      if (!c.isGranted) ok = false;
    } else if (connect.isPermanentlyDenied) {
      ok = false;
    }
    // Phone-as-relay mode needs to advertise. Available on Android 12+ only.
    try {
      final adv = Permission.bluetoothAdvertise;
      final status = await adv.status;
      if (status.isDenied || status.isRestricted) {
        final b = await adv.request();
        if (!b.isGranted) ok = false;
      } else if (status.isPermanentlyDenied) {
        ok = false;
      }
    } catch (_) {
      // Older Android / non-supported platforms: nothing to request.
    }
    return ok;
  }

  /// Scan for a SAFETRAILS relay and connect. Requires permissions.
  Future<void> connectAndListen({
    Duration scanTimeout = const Duration(seconds: 10),
    Duration connectTimeout = const Duration(seconds: 10),
    bool forceNew = false,
    Set<String> skipDeviceIds = const {},
  }) async {
    if (!forceNew && isConnected) return;
    _stateController.value = BleLinkState.scanning;
    _errorController.value = null;

    // Ensure we have the REAL adapter state. `adapterStateNow` starts as
    // `unknown` until the plugin has queried it once, so waiting on the stream
    // (which forces the read) avoids false "Bluetooth is off" errors.
    BluetoothAdapterState adapter;
    try {
      adapter = await FlutterBluePlus.adapterState
          .first
          .timeout(connectTimeout);
    } catch (_) {
      _stateController.value = BleLinkState.error;
      _errorController.value = 'Could not read Bluetooth state';
      return;
    }
    if (adapter != BluetoothAdapterState.on) {
      _stateController.value = BleLinkState.error;
      _errorController.value = 'Bluetooth is off - turn on phone Bluetooth';
      return;
    }

    BleLinkState? _fail(String msg) {
      _stateController.value = BleLinkState.error;
      _errorController.value = msg;
      return null;
    }

    BluetoothDevice? target;
    final Map<String, ScanResult> seen = {};
    final Set<String> skipDeviceIds = {};
    try {
      // IMPORTANT: do NOT pass a native service-UUID filter here. On many
      // Android phones the 128-bit service UUID is on the scan-response, which
      // the OS-level ScanFilter ignores entirely, so the relay never shows up.
      // Scan broadly and match the advertisement ourselves (name/service UUID).
      await FlutterBluePlus.startScan(
        androidUsesFineLocation: true,
        timeout: scanTimeout,
      );
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName?.toString();
          final svc = r.advertisementData.serviceUuids
              .any((u) => u.toString().toUpperCase() == StUuids.service.toUpperCase());
          final isRelay = svc ||
              (name != null && name.startsWith(StUuids.advertiseName));
          onScanSeen?.call(
              '${name ?? '<no-name>'} rssi=${r.rssi}${svc ? ' [svc]' : ''}',
              isRelay);
          seen[r.device.remoteId.str] = r;
        }
      });
      final deadline = DateTime.now().add(scanTimeout);
      while (DateTime.now().isBefore(deadline) && target == null) {
        for (final r in List.of(seen.values)) {
          final id = r.device.remoteId.str;
          if (skipDeviceIds.contains(id)) continue;
          final name = r.advertisementData.advName;
          final hasSvc = r.advertisementData
              .serviceUuids
              .any((u) => u.toString().toUpperCase() == StUuids.service.toUpperCase());
          if (hasSvc ||
              (name != null && name.toString().startsWith(StUuids.advertiseName))) {
            target = r.device;
            break;
          }
        }
        if (target == null) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
      await sub.cancel();
    } catch (e) {
      _fail('BLE scan failed: ${e.toString().split('\n').first}');
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      return;
    } finally {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    }

    if (target == null) {
      final svc = await Permission.locationWhenInUse.serviceStatus;
      // Distinguish "nothing nearby" from "only the gateway is nearby", which is
      // the expected outcome of force-relay-hop with no relay in range.
      if (skipDeviceIds.isNotEmpty && seen.isNotEmpty) {
        _fail('Only the rescue gateway is in range — no relay node found '
            '(scanned ${seen.length} devices)');
        return;
      }
      _fail(seen.isEmpty
          ? (svc != ServiceStatus.enabled
              ? 'Location services are OFF - enable Location in quick settings'
              : 'No BLE devices in range - is the relay powered & close?')
          : 'No SAFETRAILS relay nearby (scanned ${seen.length} devices)');
      return;
    }

    _device = target;
    _stateController.value = BleLinkState.connecting;
    try {
      await target.connect(timeout: connectTimeout);
    } catch (_) {
      _device = null;
      _stateController.value = BleLinkState.error;
      _errorController.value = 'Failed to connect to relay';
      return;
    }
    try {
      await _setupService();
    } catch (e) {
      _device = null;
      await target.disconnect().catchError((_) {});
      _stateController.value = BleLinkState.error;
      _errorController.value = 'Relay service setup failed';
      return;
    }
    _receiving = true;
    _stateController.value = BleLinkState.connected;
  }

  Future<void> _setupService() async {
    _teardownSubs();
    final device = _device!;
    final services = await device.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid.toString().toUpperCase() == StUuids.service.toUpperCase(),
      orElse: () => throw Exception('SAFETRAILS service not found'),
    );

    final missing = <String>[];

    // Subscribe per characteristic and tolerate the ones that are absent.
    // Failing the whole connection because one optional endpoint is missing
    // meant a single absent UUID tore down BLE entirely: the caller disconnects
    // on exception, the link retries every ~15s, and the phone received nothing
    // while the dashboard still showed the incident as delivered.
    Future<void> subscribe(String uuid, void Function(Packet) onPacket) async {
      final match = svc.characteristics.where(
        (c) => c.uuid.toString().toUpperCase() == uuid.toUpperCase(),
      );
      if (match.isEmpty) {
        missing.add(uuid);
        return;
      }
      final ch = match.first;
      try {
        await ch.setNotifyValue(true);
      } catch (e) {
        missing.add('$uuid notify failed: ${e.toString().split('\n').first}');
        return;
      }
      final sub = ch.lastValueStream.listen((value) {
        if (value.isEmpty) return;
        try {
          onPacket(Packet.fromJson(utf8.decode(value)));
        } catch (e) {
          // A malformed frame must not kill the stream: log it so an app-side
          // parse failure is distinguishable from a radio failure.
          _missingChars.add('frame rejected: ${e.toString().split('\n').first}');
        }
      });
      _subs.add(sub);
    }

    await subscribe(StUuids.sosRx, _inbound.add);
    await subscribe(StUuids.rescueRx, _inbound.add);
    await subscribe(StUuids.broadcastRx, _inbound.add);
    await subscribe(StUuids.statusRx, (p) => _nodeStatus.add(p.body));

    _missingChars
      ..clear()
      ..addAll(missing);

    // RSSI ticker while connected
    _rssiTicker?.cancel();
    _rssiTicker = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_device == null) return;
      try {
        _rssi.value = await _device!.readRssi();
      } catch (_) {}
    });
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _inbound.close();
    await _nodeStatus.close();
  }

  Future<void> disconnect() async {
    _teardownSubs();
    final d = _device;
    _device = null;
    _receiving = false;
    _errorController.value = null;
    _missingChars.clear();
    if (d != null) {
      // Awaited: a manual refresh starts scanning immediately, and without
      // waiting for the old link to drop the scan races the teardown.
      try {
        await d.disconnect().timeout(const Duration(seconds: 4));
      } catch (_) {
        // Already gone; nothing left to tear down.
      }
    }
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    _stateController.value = BleLinkState.off;
  }

  void _teardownSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _rssiTicker?.cancel();
    _rssiTicker = null;
  }

  // -------------------------------------------------------------------------

  Future<bool> _write(String uuid, Packet p, {int retries = 3}) async {
    final device = _device;
    if (device == null || !_receiving) return false;
    final services = await device.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid.toString().toUpperCase() == StUuids.service.toUpperCase(),
      orElse: () => throw Exception('SAFETRAILS service not found'),
    );
    final c = svc.characteristics.firstWhere(
      (c) => c.uuid.toString().toUpperCase() == uuid.toUpperCase(),
    );
    final bytes = Uint8List.fromList(utf8.encode(p.toJson()));
    for (var i = 0; i < retries; i++) {
      try {
        await c.write(bytes).timeout(const Duration(seconds: 5));
        return true;
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
      }
    }
    return false;
  }

  /// Send SOS packet to the connected relay.
  Future<bool> sendSos(Packet sos) => _write(StUuids.sosTx, sos);

  /// Send acknowledgement for a received broadcast/rescue message.
  Future<bool> sendAck(Packet ack) => _write(StUuids.aclTx, ack);
}