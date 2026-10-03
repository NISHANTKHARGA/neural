import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A demo emergency contact. Stored locally only.
class EmergencyContact {
  EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
  });

  final String id;
  String name;
  String phone;
  String relation;

  Map<String, String> toMap() => {'id': id, 'name': name, 'phone': phone, 'relation': relation};

  static EmergencyContact fromMap(Map<String, dynamic> m) => EmergencyContact(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        relation: m['relation'] as String? ?? 'Other',
      );
}

/// Demo session + profile. Deliberately local: nothing here is a real account
/// system and no credential ever leaves the device.
class SessionStore extends ChangeNotifier {
  static const _kLoggedIn = 'nn_logged_in';
  static const _kName = 'nn_name';
  static const _kEmail = 'nn_email';
  static const _kPassword = 'nn_password';
  static const _kContacts = 'nn_contacts';

  bool _loggedIn = false;
  String _name = '';
  String _email = '';
  String _password = '';
  List<EmergencyContact> _contacts = [];
  bool _loaded = false;

  bool get loggedIn => _loggedIn;
  String get name => _name;
  String get email => _email;
  List<EmergencyContact> get contacts => List.unmodifiable(_contacts);
  bool get loaded => _loaded;

  /// Demo subscription plan shown on the login screen. Not a real billing flow.
  static const planName = 'Neural Nexus Rescue · Explorer';
  static const planDetail = 'Demo subscription · 12 months · renews 12 Mar 2027';
  static const planBadge = 'SUBSCRIBER';

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _loggedIn = p.getBool(_kLoggedIn) ?? false;
      _name = p.getString(_kName) ?? '';
      _email = p.getString(_kEmail) ?? '';
      _password = p.getString(_kPassword) ?? '';
      final raw = p.getStringList(_kContacts) ?? const <String>[];
      _contacts = raw
          .map((e) {
            try {
              return EmergencyContact.fromMap(const JsonCodecShim().decode(e));
            } catch (_) {
              return null;
            }
          })
          .whereType<EmergencyContact>()
          .toList();
    } catch (_) {
      // prefs unavailable: stay logged out, app still usable.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Demo sign-in. Accepts any non-empty pair so the flow can be demonstrated;
  /// the stored value is only a local display name.
  Future<bool> signIn(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) return false;
    _loggedIn = true;
    _email = email.trim();
    _password = password;
    if (_name.isEmpty) {
      _name = _email.split('@').first.replaceAll(RegExp(r'[^A-Za-z0-9]'), ' ');
      if (_name.trim().isEmpty) _name = 'Rescuer';
    }
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> signOut() async {
    _loggedIn = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kLoggedIn, false);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? email, String? password}) async {
    if (name != null && name.trim().isNotEmpty) _name = name.trim();
    if (email != null && email.trim().isNotEmpty) _email = email.trim();
    if (password != null && password.isNotEmpty) _password = password;
    await _persist();
    notifyListeners();
  }

  Future<void> addContact(String name, String phone, String relation) async {
    _contacts.add(EmergencyContact(
      id: 'C${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      phone: phone.trim(),
      relation: relation,
    ));
    await _persist();
    notifyListeners();
  }

  Future<void> updateContact(EmergencyContact c, String name, String phone, String relation) async {
    c.name = name.trim();
    c.phone = phone.trim();
    c.relation = relation;
    await _persist();
    notifyListeners();
  }

  Future<void> removeContact(String id) async {
    _contacts.removeWhere((c) => c.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kLoggedIn, _loggedIn);
      await p.setString(_kName, _name);
      await p.setString(_kEmail, _email);
      await p.setString(_kPassword, _password);
      await p.setStringList(
          _kContacts, _contacts.map((c) => c.toMap().toString()).toList());
    } catch (_) {}
  }
}

/// Tiny wrapper so the decode call site stays readable without importing
/// dart:convert into the state layer's public surface.
class JsonCodecShim {
  const JsonCodecShim();
  Map<String, dynamic> decode(String s) {
    final out = <String, dynamic>{};
    // The stored form is Dart's Map.toString(); parse the simple key=value pairs.
    final inner = s.replaceAll('{', '').replaceAll('}', '');
    for (final part in inner.split(',')) {
      final i = part.indexOf(': ');
      if (i <= 0) continue;
      final k = part.substring(0, i).trim();
      var v = part.substring(i + 2).trim();
      if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
        v = v.substring(1, v.length - 1);
      }
      out[k] = v;
    }
    return out;
  }
}