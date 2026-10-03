import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_store.dart';
import '../theme/nepali.dart';

/// Demo sign-in. The subscription card is cosmetic — there is no billing call
/// and no credential leaves the device.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(SessionStore store) async {
    final e = _email.text.trim();
    final p = _password.text;
    if (e.isEmpty || p.isEmpty) {
      _toast('Enter an email and a password to continue.');
      return;
    }
    setState(() => _busy = true);
    final ok = await store.signIn(e, p);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _toast('Sign-in failed. Try any non-empty credentials.');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SessionStore>();

    return Scaffold(
      backgroundColor: Nepali.night,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _logo(),
                  const SizedBox(height: 22),
                  Text('Sign in',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Nepali.snow,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 6),
                  Text('Neural Nexus Rescue Network',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Nepali.muted, fontSize: 13, letterSpacing: 0.4)),
                  const SizedBox(height: 22),
                  _subscriptionCard(),
                  const SizedBox(height: 20),
                  _field(
                    icon: Icons.alternate_email,
                    hint: 'Email address',
                    controller: _email,
                    keyboard: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    icon: Icons.lock_outline,
                    hint: 'Password',
                    controller: _password,
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20, color: Nepali.muted),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Nepali.crimson,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                      ),
                      onPressed: _busy ? null : () => _submit(store),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white))
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => _toast('Demo build: password reset is disabled.'),
                    child: const Text('Forgot password?'),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 14, color: Nepali.muted),
                      const SizedBox(width: 6),
                      Text('Demo mode · demo@neuralnexus.app / demo1234',
                          style: TextStyle(color: Nepali.muted, fontSize: 11.5)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Column(
      children: [
        Container(
          height: 66,
          width: 66,
          decoration: BoxDecoration(
            color: Nepali.crimson,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.terrain, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 14),
        Text('SAFETRAILS',
            style: TextStyle(
                color: Nepali.snow,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 3)),
        const SizedBox(height: 2),
        Text('NEURAL NEXUS',
            style: TextStyle(
                color: Nepali.crimson,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 3.4)),
      ],
    );
  }

  Widget _subscriptionCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Nepali.panelLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Nepali.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Nepali.crimson,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(SessionStore.planBadge,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(SessionStore.planName,
                    style: TextStyle(
                        color: Nepali.snow,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(SessionStore.planDetail,
                    style: TextStyle(color: Nepali.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    bool obscure = false,
    TextInputType? keyboard,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(
        filled: true,
        fillColor: Nepali.panel,
        hintText: hint,
        hintStyle: TextStyle(color: Nepali.muted, fontSize: 14),
        prefixIcon: Icon(icon, size: 20, color: Nepali.muted),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Nepali.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Nepali.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Nepali.crimson, width: 1.6),
        ),
      ),
    );
  }
}