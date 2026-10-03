import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_store.dart';
import '../theme/nepali.dart';

/// Emergency contacts. The SOS action here is a DEMO ONLY: it shows a
/// confirmation dialog and sends nothing over BLE/LoRa. Real alerts are raised
/// from the SOS button on the Home tab, which goes through SosController.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SessionStore>();

    return Scaffold(
      backgroundColor: Nepali.night,
      appBar: AppBar(
        title: const Text('Emergency contacts'),
        backgroundColor: Nepali.panel,
        foregroundColor: Nepali.snow,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Nepali.line)),
      ),
      body: store.contacts.isEmpty
          ? _empty(context)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
              itemCount: store.contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _tile(context, store, store.contacts[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editContact(context, store, null),
        backgroundColor: Nepali.crimson,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1, size: 20),
        label: const Text('Add contact'),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.contacts_outlined, size: 54, color: Nepali.line),
            const SizedBox(height: 16),
            Text('No emergency contacts yet',
                style: TextStyle(
                    color: Nepali.snow, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Add family or a friend so the rescue desk knows who to contact '
              'for this device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Nepali.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, SessionStore store, EmergencyContact c) {
    return Container(
      decoration: BoxDecoration(
        color: Nepali.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nepali.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: Nepali.crimsonSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              c.name.isEmpty ? '?' : c.name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                  color: Nepali.crimsonDark, fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    style: TextStyle(
                        color: Nepali.snow, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${c.relation} · ${c.phone}',
                    style: TextStyle(color: Nepali.muted, fontSize: 12.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: Icon(Icons.edit_outlined, size: 19, color: Nepali.muted),
            onPressed: () => _editContact(context, store, c),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, size: 19, color: Nepali.muted),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Remove contact'),
                  content: Text('Remove ${c.name} from your emergency list?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Nepali.crimson),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
              if (ok == true) await store.removeContact(c.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editContact(BuildContext context, SessionStore store, EmergencyContact? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    var relation = existing?.relation ?? 'Family';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add emergency contact' : 'Edit contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Full name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: relation,
                  decoration: const InputDecoration(
                      labelText: 'Relationship', border: OutlineInputBorder()),
                  items: const ['Family', 'Friend', 'Neighbour', 'Work', 'Other']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => relation = v ?? relation,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Nepali.crimson),
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                if (existing == null) {
                  await store.addContact(name.text, phone.text, relation);
                } else {
                  await store.updateContact(existing, name.text, phone.text, relation);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    phone.dispose();
  }
}

/// Demo-only SOS confirmation for a contact. Nothing is transmitted.
Future<void> showDemoContactSosDialog(BuildContext context, EmergencyContact c) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.sos_rounded, color: Nepali.crimson, size: 40),
      title: const Text('Send demo SOS alert'),
      content: Text(
        'This would alert ${c.name} (${c.phone}) with your live location.\n\n'
        'Demo build: nothing is sent. Use the SOS button on the Home tab for a '
        'real alert over BLE and LoRa.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Nepali.crimson),
          onPressed: () {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text('Demo: SOS alert to ${c.name} was NOT sent.'),
              ));
          },
          child: const Text('Send demo SOS'),
        ),
      ],
    ),
  );
}