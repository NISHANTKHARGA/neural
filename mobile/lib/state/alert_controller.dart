import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:safetrails_protocol/packet.dart';

enum Severity { low, medium, high, critical }

class EmergencyAlert {
  EmergencyAlert({
    required this.packet,
    required this.seenAt,
    required this.acknowledged,
  });

  final Packet packet;
  final DateTime seenAt;
  bool acknowledged;

  String get title {
    switch (packet.type) {
      case 'RESCUE':
        return 'Rescue message';
      case 'BROAD':
        return switch (packet.prio) {
          3 => '🚨 CRITICAL EMERGENCY',
          2 => '⚠️ HIGH ALERT',
          1 => '⚠️ MEDIUM ALERT',
          _ => 'ℹ️ LOW ALERT',
        };
      default:
        return 'SAFETRAILS message';
    }
  }

  Severity get severity => switch (packet.prio) {
        0 => Severity.low,
        1 => Severity.medium,
        2 => Severity.high,
        _ => Severity.critical,
      };
}

extension SeverityLabel on Severity {
  String get label => switch (this) {
        Severity.low => 'LOW',
        Severity.medium => 'MEDIUM',
        Severity.high => 'HIGH',
        Severity.critical => 'CRITICAL',
      };
}

/// Emergency alert: plays the bundled siren for ~5 seconds plus 5 vibration
/// blips. Uses audioplayers with a local asset so the sound works fully offline
/// and is not subject to the device's system-tone settings.
class AlertSound {
  static const _sirenSecs = 5;
  static Timer? _ringTimer;
  static int _beeps = 0;
  static AudioPlayer? _player;

  static Future<void> play() async {
    _ringTimer?.cancel();
    _beeps = 0;
    await _startSiren();
    _ringTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_beeps >= _sirenSecs) {
        t.cancel();
        _ringTimer = null;
        HapticFeedback.heavyImpact();
      } else {
        _beeps++;
        HapticFeedback.heavyImpact();
      }
    });
  }

  static Future<void> _startSiren() async {
    try {
      final p = _player ??= AudioPlayer();
      p.setReleaseMode(ReleaseMode.loop);
      p.setVolume(1.0);
      await p.stop();
      await p.play(AssetSource('siren.wav'));
      // Stop the loop when the 5s window ends.
      Future<void>.delayed(const Duration(seconds: _sirenSecs)).then((_) {
        try {
          if (_player != null) {
            _player!.stop();
          }
        } catch (_) {}
      });
    } catch (_) {
      // fall back to the platform tone if the player is unavailable
      SystemSound.play(SystemSoundType.alert);
    }
  }

  static void stop() {
    _ringTimer?.cancel();
    _ringTimer = null;
    try {
      if (_player != null) _player!.stop();
    } catch (_) {}
  }
}

/// Incoming emergency broadcasts / rescue messages pushed over BLE.
/// Supports explicit acknowledgement back to the rescue side.
class AlertController extends ChangeNotifier {
  AlertController();

  final Map<String, EmergencyAlert> _byMid = {};
  List<EmergencyAlert> get alerts {
    final list = _byMid.values.toList();
    list.sort((a, b) => b.seenAt.compareTo(a.seenAt));
    return list;
  }

  bool get hasUnread => alerts.any((a) => !a.acknowledged && a.packet.type == 'BROAD');

  void absorb(Packet p) {
    if (p.type != 'BROAD' && p.type != 'RESCUE') return;
    final mid = p.mid;
    if (mid == null || mid.isEmpty) return;
    if (_byMid.containsKey(mid)) return; // duplicate broadcast
    _byMid[mid] = EmergencyAlert(
      packet: p,
      seenAt: DateTime.now(),
      acknowledged: false,
    );
    AlertSound.play();
    notifyListeners();
  }

  Future<bool> acknowledge(EmergencyAlert alert, {required Future<bool> Function(Packet) sender}) async {
    final ack = PacketFactory.ackFor(alert.packet);
    final ok = await sender(ack);
    if (ok) {
      alert.acknowledged = true;
      notifyListeners();
    }
    return ok;
  }
}