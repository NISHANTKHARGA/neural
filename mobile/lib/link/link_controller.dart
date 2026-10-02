import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:safetrails_protocol/packet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_relay_connection.dart';
import '../ble/phone_peripheral.dart';

/// Reachable transports, ranked by the mobile app's priority.
/// The phone has no LoRa radio itself: "LoRa" means it is BLE-linked to a
/// relay node whose LoRa radio is up and recently heard (reach=1).
enum LinkTransport { lora, ble, online, offline }

extension LinkTransportLabel on LinkTransport {
  String get label => switch (this) {
        LinkTransport.lora => 'LoRa connected',
        LinkTransport.ble => 'BLE connected',
        LinkTransport.online => 'Online',
        LinkTransport.offline => 'No link',
      };

  String get short => switch (this) {
        LinkTransport.lora => 'LoRa',
        LinkTransport.ble => 'BLE',
        LinkTransport.online => 'Online',
        LinkTransport.offline => 'OFF',
      };
}

/// Parsed relay link-health fields (see statusBody() in relay_engine.cpp).
class LinkHealth {
  const LinkHealth({
    required this.loraUp,
    required this.loraReach,
    required this.rssiDb,
    required this.node,
  });
  final bool loraUp;
  final bool loraReach;
  final int? rssiDb;
  final String node;

  bool get loRaIsLive => loraUp && loraReach;
}

/// Watches the BLE relay link + STATUS heartbeats and the online server to
/// compute the best transport, routes SOS packets, and runs the phone-as-relay
/// BLE mesh (a peer phone with no internet can hand packets to this phone,
/// which forwards them to the hub over the internet — or onward along the
/// BLE/LoRa mesh).
class LinkController extends ChangeNotifier {
  LinkController({
    required this.relay,
    this.serverUrl = LinkController.defaultServerUrl,
  });

  /// Hub address on the rescuer PC. Update if the PC's Wi-Fi IP changes.
  static const String defaultServerUrl = 'http://192.168.1.68:8080';

  final BleRelayConnection relay;
  String serverUrl;

  StreamSubscription<dynamic>? _statusSub;
  StreamSubscription<dynamic>? _relayPacketSub;
  StreamSubscription<dynamic>? _peerSub;
  StreamSubscription<dynamic>? _periphLifecycleSub;
  Timer? _onlineTimer;
  Timer? _retryTimer;
  Timer? _announceTimer;
  bool _connecting = false;

  bool _loraUp = false;
  bool _loraReach = false;
  int? _loraRssi;
  String _relayNode = '';
  bool _onlineReachable = false;
  bool _started = false;

  // --- phone-as-relay mesh state -------------------------------------------
  final PhonePeripheral peripheral = PhonePeripheral();
  final String myNodeId = _newNodeId();
  bool _peerConnected = false;
  bool _advertising = false;
  bool _lastAnnounceOutstanding = false;
  final List<String> _seenMids = []; // small LRU (ring) for forwarding dedupe
  final Map<String, int> _seenAt = {}; // mid -> epoch seconds expiry

  /// Ring buffer of recent dispatch events so the cause of a failure is
  /// visible on the phone itself (no PC needed).
  final List<String> debugLog = [];
  void _log(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    debugLog.insert(0, '$t  $line');
    if (debugLog.length > 30) debugLog.removeLast();
    notifyListeners();
  }

  bool get onlineReachable => _onlineReachable;
  String? get relayNode => _relayNode.isEmpty ? null : _relayNode;
  int? get loraRssi => _loraRssi;
  bool get loRaIsLive => _loraUp && _loraReach;
  bool get peerModeRunning => _advertising;
  bool get peerConnected => _peerConnected;

  // ---- force-relay-hop (field-test switch) -----------------------------------
  // Every node — relay or gateway — advertises the same SAFETRAILS service, so
  // the phone normally links to whichever it hears first. With this on, a link
  // to the rescue gateway (node RCUE) is dropped on its first STATUS, forcing
  // SOS to reach the dashboard the way it does in the field: phone BLE → relay
  // → LoRa → gateway → USB serial. Off by default: never let a test aid cost us
  // an alert just because the phone happened to be standing next to RCUE.
  static const _kForceRelayHop = 'force_relay_hop';
  bool _forceRelayHop = false;
  final Set<String> _gatewayDeviceIds = {};
  DateTime _gatewayRejectedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool get forceRelayHop => _forceRelayHop;
  String? get relayHopNote {
    if (!_forceRelayHop) return null;
    return _gatewayDeviceIds.isNotEmpty
        ? 'gateway RCUE ignored — relay required'
        : 'relay required — waiting for a relay node';
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _forceRelayHop = prefs.getBool(_kForceRelayHop) ?? false;
      notifyListeners();
    } catch (_) {
      // prefs unavailable: keep the safe default (gateway allowed)
    }
  }

  Future<void> setForceRelayHop(bool value) async {
    if (_forceRelayHop == value) return;
    _forceRelayHop = value;
    _gatewayRejectedUntil = DateTime.fromMillisecondsSinceEpoch(0);
    // Turning the switch off must make the gateway usable again immediately.
    if (!value) _gatewayDeviceIds.clear();
    notifyListeners();
    _log(value
        ? 'force relay hop ON · gateway link will be refused'
        : 'force relay hop OFF · any node may be used');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kForceRelayHop, value);
    } catch (_) {
      // non-fatal: setting stays for this session only
    }
    if (bleConnected) unawaited(_rejectGatewayLink());
    else unawaited(_autoConnect());
  }

  /// Refuse a gateway link. The node id is only learnable after connecting, so
  /// the gateway's BLE address is blacklisted: subsequent scans skip it outright
  /// instead of connecting, waiting for STATUS, and dropping again.
  Future<void> _rejectGatewayLink() async {
    final id = relay.connectedDeviceId;
    if (id != null) _gatewayDeviceIds.add(id);
    final now = DateTime.now();
    if (now.isBefore(_gatewayRejectedUntil)) return;
    _log('linked to gateway RCUE · refusing (force relay hop)'
        '${id == null ? '' : ' · ignoring ${id.substring(id.length - 5)}'}');
    _relayNode = '';
    await relay.disconnect();
    // The gateway address is now blacklisted, so scanning again cannot grab it
    // again -- no reason to sit disconnected waiting out the cooldown, which
    // left the UI reading "BLE unavailable" for 20s after a deliberate switch.
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _autoConnect();
  }

  String? _peerError;
  String? get peerError => _peerError;

  /// Force-relay-hop is on but we are not linked yet: the UI should say we are
  /// hunting a relay rather than reporting the link as unavailable.
  bool get huntingRelay =>
      _forceRelayHop &&
      !bleConnected &&
      relay.state.value != BleLinkState.connecting;

  /// True when the BLE "error" is really just "no relay node in range yet".
  /// Those messages are expected while force-relay-hop is on, so they must not
  /// be dressed up as a failure -- the scan simply retries every 10s.
  bool get relayAbsent {
    if (!_forceRelayHop || bleConnected) return false;
    final e = (relay.error.value ?? '').toLowerCase();
    return e.contains('no safetrails relay') ||
        e.contains('only the rescue gateway') ||
        e.contains('no ble devices');
  }

  static String _newNodeId() {
    final r = Random();
    final hex =
        List.generate(4, (_) => r.nextInt(16).toRadixString(16).toUpperCase()).join();
    return 'P-$hex';
  }

  bool get bleConnected =>
      relay.state.value == BleLinkState.connected;
  bool get bleBusy => relay.state.value == BleLinkState.scanning ||
      relay.state.value == BleLinkState.connecting;

  /// Effective transport with priority LoRa > BLE > Online.
  LinkTransport get active {
    if (relay.state.value == BleLinkState.connected) {
      return loRaIsLive ? LinkTransport.lora : LinkTransport.ble;
    }
    if (_onlineReachable) return LinkTransport.online;
    return LinkTransport.offline;
  }

  String get statusLabel => active.label;

  void start() {
    if (_started) return;
    _started = true;
    _statusSub = relay.nodeStatus.listen(_onStatus);
    _relayPacketSub = relay.packets.listen(_onRelayPacketForMesh);
    relay.state.addListener(_onRelayState);
    _onlineTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => probeOnline(),
    );
    _retryTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _autoConnect(),
    );
    probeOnline();
    _autoConnect();
    loadSettings();
    _periphLifecycleSub = peripheral.lifecycle.listen(_onPeripheralLifecycle);
    _peerSub = peripheral.peerPackets.listen(_onPeerPacket);
    peripheral.init().then((_) => _maybeStartPeripheral());
    _announceTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _announce(),
    );
    _log('app start · node $myNodeId · hub $serverUrl');
  }

  void _onRelayState() {
    notifyListeners();
    final s = relay.state.value;
    if (s == BleLinkState.error && relay.error.value != null) {
      _log('BLE client: ${relay.error.value}');
    } else if (s == BleLinkState.connected) {
      _log('BLE client connected to ${relayNode ?? 'relay'}');
    }
  }

  // -------------------------------------------------------------------------
  // BLE link establishment. The phone reaches LoRa only through a linked
  // relay, so the link controller itself is what drives connect+retry. This
  // runs automatically and is also invoked before any SOS transmission.
  // -------------------------------------------------------------------------

  Future<void> _autoConnect() async {
    if (_connecting) return;
    if (bleConnected || bleBusy) return;
    // No cooldown gate here on purpose: _gatewayRejectedUntil only stops the
    // refuse->regrab cycle in _rejectGatewayLink, while the gateway address
    // blacklist is what actually keeps the scan off the gateway. Gating scans
    // on the cooldown left the link dead for 20s after every deliberate switch.
    _connecting = true;
    try {
      final permsOk = await relay.ensurePermissions();
      if (!permsOk) {
        relay.reportError(
            'Permissions needed - enable Bluetooth & Location for SAFETRAILS');
        notifyListeners();
        return;
      }
      relay.onScanSeen = (desc, isRelay) =>
          _log(isRelay
              ? 'scan: SAFETRAILS seen · $desc'
              : 'scan: other $desc');
      await relay.connectAndListen(
        scanTimeout: const Duration(seconds: 10),
        connectTimeout: const Duration(seconds: 10),
        skipDeviceIds: _gatewayDeviceIds,
      );
      relay.onScanSeen = null;
      if (relay.state.value == BleLinkState.connected) {
        _log('BLE client connected (${relayNode ?? 'relay'})');
        _announce();
      } else if (relay.state.value == BleLinkState.error) {
        _log('BLE client error: ${relay.error.value}');
      } else {
        _log('BLE client idle after scan');
      }
    } catch (_) {
      // keep retrying on the next timer tick
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Ensure a BLE relay link is established before transmitting, so SOS
  /// works even when only LoRa/BLE (no internet) is reachable.
  Future<bool> ensureLink() async {
    if (bleConnected) return true;
    if (!bleBusy) await _autoConnect();
    // Give a mid-flight connect up to ~18s to complete.
    final deadline = DateTime.now().add(const Duration(seconds: 18));
    while (!bleConnected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return bleConnected;
  }

  void _onStatus(String body) {
    final h = parseStatusBody(body);
    _loraUp = h.loraUp;
    _loraReach = h.loraReach;
    _loraRssi = h.rssiDb;
    if (h.node.isNotEmpty) _relayNode = h.node;
    notifyListeners();
    // The node id is only knowable after connecting, so this is where a
    // gateway link gets refused (see forceRelayHop).
    if (_forceRelayHop && h.node == 'RCUE') unawaited(_rejectGatewayLink());
  }

  /// Parses `key=value` pairs from a relay STATUS body:
  /// `node=N-A role=relay lora=1 reach=1 rssi=-68.4 snr=...`
  static LinkHealth parseStatusBody(String body) {
    bool? loraUp;
    bool? reach;
    int? rssi;
    String node = '';
    for (final pair in body.split(' ')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq);
      final val = pair.substring(eq + 1);
      switch (key) {
        case 'lora':
          loraUp = val == '1';
        case 'reach':
          reach = val == '1';
        case 'rssi':
          rssi = double.tryParse(val)?.round();
        case 'node':
          node = val;
      }
    }
    return LinkHealth(
      loraUp: loraUp ?? false,
      loraReach: reach ?? false,
      rssiDb: rssi,
      node: node,
    );
  }

  Future<void> probeOnline() async {
    final ok = await _checkHealth();
    if (ok != _onlineReachable) {
      _onlineReachable = ok;
      notifyListeners();
    }
  }

  Future<bool> _checkHealth() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(Uri.parse('$serverUrl/api/health'));
      final res = await req.close();
      await res.drain<void>();
      client.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Send an SOS over the best reachable transport.
  ///
  /// Priority:
  ///   1. Online (internet) — if the hub is reachable the SOS goes straight
  ///      to the rescuer dashboard ("direct to dashboard").
  ///   2. BLE link (to an ESP32 relay or a peer phone) → LoRa/BLE mesh, which
  ///      works with zero internet.
  /// Returns the transport used, or null on failure.
  Future<LinkTransport?> sendSos(Packet p) async {
    if (_onlineReachable) {
      if (await _postOnline(p)) return LinkTransport.online;
    }
    await ensureLink();
    if (bleConnected) {
      if (await relay.sendSos(p)) {
        return loRaIsLive ? LinkTransport.lora : LinkTransport.ble;
      }
    }
    // Online state may have changed while we waited for the link.
    if (_onlineReachable) {
      if (await _postOnline(p)) return LinkTransport.online;
    }
    return null;
  }

  /// Manual re-check from the UI: force a BLE link attempt + status refresh.
  Future<void> refresh() async {
    await probeOnline();
    await ensureLink();
    await _maybeStartPeripheral();
  }

  /// Hard refresh: tear the BLE link down and scan again from scratch.
  ///
  /// [refresh] deliberately no-ops while a link is up, which is right for a
  /// status poll but useless when the phone is attached to the wrong node or a
  /// wedged socket refuses new packets -- previously the only cure was closing
  /// and reopening the app. This drops the link, clears the refuse cooldown so
  /// the scan can run immediately, and reconnects.
  Future<void> reconnectLink() async {
    _log('refresh: dropping BLE link and rescanning');
    _connecting = true; // hold off the auto-retry timer while we do this
    try {
      await relay.disconnect();
      _relayNode = '';
      // A gateway refused a moment ago may be the node we want now (the user
      // just toggled Force relay hop off), so don't sit out the cooldown.
      _gatewayRejectedUntil = DateTime.now().subtract(const Duration(seconds: 1));
    } catch (e) {
      _log('refresh: teardown error ${e.toString().split('\n').first}');
    } finally {
      _connecting = false;
    }
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _autoConnect();
  }

  /// Eagerly ask for Bluetooth/Location permissions right when the app opens,
  /// then immediately attempt to link to the relay. Idempotent: the OS only
  /// shows a dialog the first time; later calls return the decided state.
  Future<void> startupPermissions() async {
    final ok = await relay.ensurePermissions();
    if (!ok) {
      relay.reportError(
          'Permissions needed - enable Bluetooth & Location for SAFETRAILS');
      notifyListeners();
      return;
    }
    notifyListeners();
    await _maybeStartPeripheral();
    await _autoConnect();
  }

  // -------------------------------------------------------------------------
  // Phone-as-relay BLE mesh
  //
  // Every phone advertises as a SAFETRAILS relay (GATT server). A peer phone
  // with no internet may connect to this phone and write its SOS. We then:
  //   - if the hub is reachable → POST it to the dashboard straight away and
  //     reply with an ACK back to the peer over BLE (so the sender sees it was
  //     delivered), otherwise
  //   - forward it on to any relay we are linked to (LoRa/BLE chain).
  // We also mirror RESCUE/BROAD packets we receive from our own relay out to
  // connected peer phones, so offline peers still get alarms from the desk.
  // -------------------------------------------------------------------------

  Future<void> _maybeStartPeripheral() async {
    final permsOk = await relay.ensurePermissions();
    if (!permsOk) {
      _log('peripheral skipped: permissions not granted');
      return;
    }
    for (var attempt = 1; attempt <= 4; attempt++) {
      final ok = await peripheral.start(name: 'SAFETRAILS_RELAY');
      if (ok) {
        _log('peripheral start OK · advertising as $myNodeId');
        return;
      }
      _log('peripheral start FAILED (attempt $attempt/4) — retrying…');
      await Future<void>.delayed(const Duration(milliseconds: 3000));
    }
  }

  void _onPeripheralLifecycle(Map<String, dynamic> evt) {
    final kind = evt['evt'] as String? ?? '';
    _log('peer event: $kind${kind == 'advertisingStopped' ? ' (${evt['code']})' : ''}');
    switch (kind) {
      case 'advertisingStarted':
        _advertising = true;
        _peerError = null;
      case 'advertisingStopped':
        _advertising = false;
        final code = evt['code'];
        _peerError = 'Advertising failed: $code';
      case 'connecting':
        _peerConnected = true;
        _announce();
      case 'subscribed':
        // A client enabled notifications; make sure the announce is pushed.
        if (_peerConnected) _announce();
      case 'clientDisconnected':
        _peerConnected = false;
        _peerError = null;
    }
    notifyListeners();
  }

  /// Reject a packet we already forwarded within the last 90s (mesh storm
  /// protection). The LRU is tiny because only emergency traffic flows here.
  bool _seenRecently(String mid) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expire = _seenAt.remove(mid);
    if (expire != null && now < expire) return true;
    _seenMids.remove(mid);
    if (_seenMids.length >= 64) {
      final oldest = _seenMids.removeAt(0);
      _seenAt.remove(oldest);
    }
    _seenMids.add(mid);
    _seenAt[mid] = now + 90;
    return false;
  }

  void _onPeerPacket(PeerWrite w) {
    if (!w.isEmergency || !_peerConnected) return;
    final Packet p;
    try {
      p = Packet.fromJson(w.data);
    } catch (_) {
      return; // malformed / bad checksum — ignore
    }
    if (!['SOS', 'RESCUE', 'BROAD'].contains(p.type)) return;
    if (p.hop >= 15) return;
    if (_seenRecently(p.mid ?? '')) return;
    _forwardFromPeer(p);
  }

  Future<void> _forwardFromPeer(Packet p) async {
    // 1. Best case: the hub is reachable from this phone's internet.
    if (_onlineReachable) {
      final ok = await _postOnline(p);
      if (ok) {
        if (p.type == 'SOS') {
          // Look like the rescue desk so the sender's app shows ACKNOWLEDGED.
          final ack = PacketFactory.ackFor(p, from: 'RCUE');
          await peripheral.notifyPacket(StUuids.sosRx, ack);
        }
        return;
      }
    }
    // 2. Offline: pass it up the BLE/LoRa chain via any linked relay. The node
    //    floods LoRa *and* BLE when the radio is unreachable, so a packet still
    //    reaches the desk with no working LoRa link at all.
    if (bleConnected) {
      unawaited(relay.sendSos(p));
      return;
    }
    // 3. No node link and no internet: extend the chain to another phone that
    //    may be closer to a node instead of dropping the alert on the floor.
    //    Bounded by hop<15 plus the receiver's own _seenRecently dedup.
    if (_peerConnected) {
      _log('peer ${p.type} ${p.mid} · no node link · relaying via peers');
      final char = switch (p.type) {
        'RESCUE' => StUuids.rescueRx,
        'BROAD' => StUuids.broadcastRx,
        _ => StUuids.sosRx,
      };
      unawaited(peripheral.notifyPacket(char, p..hop = p.hop + 1));
      return;
    }
    // 4. Nowhere left to send it. A silent drop looks exactly like "nobody
    //    responded" on the tourist's phone, which is the worst possible
    //    failure mode for a rescue system -- so say it out loud.
    _peerError =
        'Peer ${(p.type ?? 'packet').toLowerCase()} ${p.mid} not sent: '
        'no internet, no relay link';
    _log(_peerError!);
    notifyListeners();
  }

  /// RESCUE/BROAD/ACK coming from our own relay (from the desk / LoRa mesh) are
  /// mirrored to connected peer phones so offline phones still hear alarms and
  /// can see their SOS acknowledged. ACK was previously dropped here, which
  /// left a tourist who relayed via a phone stuck on "sent" forever.
  void _onRelayPacketForMesh(dynamic raw) {
    if (!_peerConnected) return;
    final p = raw is Packet ? raw : null;
    if (p == null || !['RESCUE', 'BROAD', 'ACK'].contains(p.type)) return;
    final char = switch (p.type) {
      'RESCUE' => StUuids.rescueRx,
      'BROAD' => StUuids.broadcastRx,
      _ => StUuids.sosRx,
    };
    unawaited(peripheral.notifyPacket(char, p));
  }

  /// STATUS announce so a peer phone can display which node it is linked to,
  /// exactly like the firmware relay heartbeat (lora=0: a phone has no radio).
  Future<void> _announce() async {
    if (!_peerConnected) return;
    if (_lastAnnounceOutstanding) return;
    _lastAnnounceOutstanding = true;
    try {
      final st = Packet()
        ..type = 'STATUS'
        ..prio = 0
        ..mid = 'ST${DateTime.now().millisecondsSinceEpoch}'
        ..src = myNodeId
        ..dst = '*'
        ..ts = DateTime.now().millisecondsSinceEpoch ~/ 1000
        ..hop = 0
        ..ttl = 1
        ..flags = 0
        ..body = 'node=$myNodeId role=phone lora=0 reach=0 rssi=0';
      await peripheral.notifyPacket(StUuids.statusRx, st);
    } finally {
      _lastAnnounceOutstanding = false;
    }
  }

  Future<bool> _postOnline(Packet p) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.postUrl(Uri.parse('$serverUrl/api/packet'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(p.toJson()));
      final res = await req.close();
      await res.drain<void>();
      final ok = res.statusCode == 200;
      client.close();
      if (!ok) _onlineReachable = false;
      return ok;
    } catch (_) {
      _onlineReachable = false;
      notifyListeners();
      return false;
    }
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _statusSub?.cancel();
    _statusSub = null;
    _relayPacketSub?.cancel();
    _relayPacketSub = null;
    _peerSub?.cancel();
    _peerSub = null;
    _periphLifecycleSub?.cancel();
    _periphLifecycleSub = null;
    _onlineTimer?.cancel();
    _onlineTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _announceTimer?.cancel();
    _announceTimer = null;
    relay.state.removeListener(notifyListeners);
    unawaited(peripheral.stop());
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}