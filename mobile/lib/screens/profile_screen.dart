import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_store.dart';
import '../theme/nepali.dart';
import 'contacts_screen.dart';

/// Profile / account. All fields are local demo values.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SessionStore>();

    return Scaffold(
      backgroundColor: Nepali.night,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Nepali.panel,
        foregroundColor: Nepali.snow,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Nepali.line)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        children: [
          _identity(store),
          const SizedBox(height: 18),
          _card(
            title: 'Account details',
            children: [
              _row(Icons.person_outline, 'Display name', store.name),
              _row(Icons.alternate_email, 'Email', store.email),
              _row(Icons.phone_iphone, 'Phone number',
                  store.email.isEmpty ? 'Not set' : _phoneFromEmail(store.email)),
              const Divider(height: 22, color: Nepali.line),
              _action(
                icon: Icons.badge_outlined,
                label: 'Change name & phone',
                onTap: () => _editIdentity(context, store),
              ),
              _action(
                icon: Icons.lock_outline,
                label: 'Change password',
                onTap: () => _editPassword(context, store),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Subscription',
            children: [
              _row(Icons.workspace_premium_outlined, 'Plan', SessionStore.planName),
              _row(Icons.event_outlined, 'Renews', '12 Mar 2027'),
              const Divider(height: 22, color: Nepali.line),
              _action(
                icon: Icons.credit_card_outlined,
                label: 'Payment method',
                onTap: () => _demo(context, 'Payment method is managed by Neural Nexus billing.'),
              ),
              _action(
                icon: Icons.help_outline,
                label: 'Manage plan',
                onTap: () => _demo(context, 'Demo build: plan management is disabled.'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Emergency contacts',
            children: [
              Text(
                store.contacts.isEmpty
                    ? 'No contacts added yet.'
                    : store.contacts
                        .map((c) => '${c.name} · ${c.relation}')
                        .join('\n'),
                style: TextStyle(color: Nepali.muted, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 10),
              if (store.contacts.isNotEmpty)
                for (final c in store.contacts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Nepali.crimsonSoft,
                      child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                          style: const TextStyle(
                              color: Nepali.crimsonDark, fontWeight: FontWeight.w800)),
                    ),
                    title: Text(c.name,
                        style: TextStyle(
                            color: Nepali.snow, fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text('${c.relation} · ${c.phone}',
                        style: TextStyle(color: Nepali.muted, fontSize: 12)),
                    trailing: OutlinedButton.icon(
                      icon: const Icon(Icons.sos, size: 15),
                      label: const Text('SOS'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Nepali.crimson,
                        side: const BorderSide(color: Nepali.crimson),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => showDemoContactSosDialog(context, c),
                    ),
                  ),
              const SizedBox(height: 6),
              _action(
                icon: Icons.contacts_outlined,
                label: 'Manage emergency contacts',
                onTap: () => _demo(context, 'Use the Contacts tab to add or remove contacts.'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Network',
            children: [
              _row(Icons.bluetooth, 'Phone as relay', 'Advertising'),
              _row(Icons.wifi_tethering, 'Subscription', SessionStore.planBadge),
              const Divider(height: 22, color: Nepali.line),
              _action(
                icon: Icons.logout,
                label: 'Sign out',
                danger: true,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sign out'),
                      content: const Text('Sign out of SAFETRAILS on this device?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Nepali.crimson),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await store.signOut();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _phoneFromEmail(String email) {
    // Demo only: derive a placeholder number from the local part.
    final local = email.split('@').first.replaceAll(RegExp(r'[^0-9]'), '');
    if (local.isEmpty) return 'Not set';
    final p = local.padRight(10, '9');
    return '+977 ${p.substring(0, 3)} ${p.substring(3, 6)} ${p.substring(6)}';
  }

  Widget _identity(SessionStore store) {
    return Row(
      children: [
        Container(
          height: 58,
          width: 58,
          decoration: BoxDecoration(
            color: Nepali.crimson,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(
            store.name.isEmpty ? '?' : store.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(store.name.isEmpty ? 'Rescuer' : store.name,
                  style: TextStyle(
                      color: Nepali.snow, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(store.email,
                  style: TextStyle(color: Nepali.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Nepali.crimsonSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(SessionStore.planBadge,
                    style: const TextStyle(
                        color: Nepali.crimsonDark,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Nepali.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nepali.line),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  color: Nepali.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Nepali.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(color: Nepali.muted, fontSize: 13)),
          ),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Nepali.snow,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: danger ? Nepali.crimson : Nepali.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: danger ? Nepali.crimson : Nepali.snow,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right, size: 18, color: Nepali.muted),
          ],
        ),
      ),
    );
  }

  void _demo(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Demo: $msg')));
  }

  Future<void> _editIdentity(BuildContext context, SessionStore store) async {
    final name = TextEditingController(text: store.name);
    final email = TextEditingController(text: store.email);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change name & phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration:
                  const InputDecoration(labelText: 'Display name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email / phone', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nepali.crimson),
            onPressed: () async {
              await store.updateProfile(name: name.text, email: email.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    email.dispose();
  }

  Future<void> _editPassword(BuildContext context, SessionStore store) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: current,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'New password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Confirm new password', border: OutlineInputBorder()),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: const TextStyle(color: Nepali.crimson, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Nepali.crimson),
              onPressed: () {
                if (next.text != confirm.text) {
                  setLocal(() => error = 'New passwords do not match');
                  return;
                }
                if (next.text.length < 4) {
                  setLocal(() => error = 'Use at least 4 characters');
                  return;
                }
                store.updateProfile(password: next.text);
                Navigator.pop(ctx);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
  }
}