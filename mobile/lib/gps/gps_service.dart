import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsStatus { ready, locating, unavailable, denied }

/// GPS wrapper. Reads coordinates from GNSS satellites directly — no
/// Internet required. (Only map tiles / geocoding need data.)
class GpsService {
  GpsService();

  final _status = ValueNotifier<GpsStatus>(GpsStatus.locating);
  ValueNotifier<GpsStatus> get status => _status;

  Position? _last;
  Position? get last => _last;

  Future<bool> ensurePermission() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _status.value = GpsStatus.denied;
      return false;
    }
    var granted = await Geolocator.checkPermission();
    if (granted == LocationPermission.denied) {
      granted = await Geolocator.requestPermission();
    }
    if (granted == LocationPermission.denied ||
        granted == LocationPermission.deniedForever) {
      _status.value = GpsStatus.denied;
      return false;
    }
    return true;
  }

  /// Acquire a fix with a timeout. Works offline (satellites).
  Future<Position?> getPosition({Duration timeout = const Duration(seconds: 20)}) async {
    if (!await ensurePermission()) return null;
    _status.value = GpsStatus.locating;
    try {
      _last = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _status.value = GpsStatus.ready;
      return _last;
    } on TimeoutException {
      // geolocator may throw TimeoutException when fix exceeds timeLimit
    } catch (e) {
      _status.value = GpsStatus.unavailable;
    }
    // Fallback with a short timeout so UI can decide.
    try {
      _last = await Geolocator.getLastKnownPosition();
      if (_last != null) {
        _status.value = GpsStatus.ready;
        return _last;
      }
    } catch (_) {}
    _status.value = GpsStatus.unavailable;
    return null;
  }
}