import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_relay_connection.dart';
import '../gps/gps_service.dart';
import '../link/link_controller.dart';
import '../state/alert_controller.dart';
import '../state/sos_controller.dart';
import '../theme/nepali.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleRelayConnection>();
    final sos = context.watch<SosController>();
    final gps = context.watch<GpsService>();
    final alerts = context.watch<AlertController>();
    final link = context.watch<LinkController>();

    return Scaffold(
      backgroundColor: Nepali.night,
      body: SafeArea(
        child: Column(
          children: [
            const _BrandHeader(),
            if (alerts.hasUnread) _EmergencyBanner(alerts: alerts, ble: ble),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _SosButton(sos: sos),
                    _StatusPanel(ble: ble, gps: gps, sos: sos, link: link),
                    if (alerts.alerts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _AlertsSection(alerts: alerts, ble: ble),
                    ],
                    if (sos.messages.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _HistorySection(sos: sos),
                    ],
                    const SizedBox(height: 16),
                    _DebugSection(log: link.debugLog),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SAFETRAILS wordmark + Devanagari tagline over the Himalaya banner.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 14, bottom: 2),
          child: Text(
            'SAFETRAILS',
            style: TextStyle(
              color: Nepali.snow,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              shadows: [
                Shadow(color: Nepali.crimson, blurRadius: 18, offset: Offset(0, 2)),
              ],
            ),
          ),
        ),
        const Text(
          'हिमालय उद्धार नेटवर्क · Offline Emergency Network',
          textAlign: TextAlign.center,
          style: TextStyle(color: Nepali.gold, fontSize: 12, letterSpacing: 0.6),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 118,
          child: CustomPaint(painter: _HimalayaPainter()),
        ),
      ],
    );
  }
}

/// Himalaya ridges in crimson, with the summit marked — the app's visual identity.
class _HimalayaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Far ridges.
    final far = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.72)
      ..lineTo(w * 0.16, h * 0.52)
      ..lineTo(w * 0.30, h * 0.70)
      ..lineTo(w * 0.46, h * 0.48)
      ..lineTo(w * 0.62, h * 0.66)
      ..lineTo(w * 0.78, h * 0.44)
      ..lineTo(w * 0.92, h * 0.64)
      ..lineTo(w, h * 0.56)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFFF2C6CD));

    // The big Sagarmatha massif in front.
    final ridge = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.86)
      ..lineTo(w * 0.12, h * 0.66)
      ..lineTo(w * 0.26, h * 0.78)
      ..lineTo(w * 0.40, h * 0.80)
      ..lineTo(w * 0.55, h * 0.34) // Everest summit
      ..lineTo(w * 0.66, h * 0.58)
      ..lineTo(w * 0.80, h * 0.72)
      ..lineTo(w * 0.92, h * 0.62)
      ..lineTo(w, h * 0.78)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(ridge, Paint()..color = Nepali.crimson);

    // Snow cap on the summit.
    final cap = Path()
      ..moveTo(w * 0.49, h * 0.62)
      ..lineTo(w * 0.55, h * 0.34)
      ..lineTo(w * 0.61, h * 0.52)
      ..lineTo(w * 0.57, h * 0.55)
      ..lineTo(w * 0.55, h * 0.52)
      ..lineTo(w * 0.53, h * 0.60)
      ..close();
    canvas.drawPath(cap, Paint()..color = Colors.white);

    // Summit marker.
    final marker = Paint()
      ..color = Nepali.crimsonDark
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(w * 0.55, h * 0.10), Offset(w * 0.55, h * 0.20), marker);
    canvas.drawLine(
        Offset(w * 0.52, h * 0.15), Offset(w * 0.58, h * 0.15), marker);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SosButton extends StatefulWidget {
  const _SosButton({required this.sos});
  final SosController sos;

  @override
  State<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<_SosButton> {
  final _msg = TextEditingController();

  SosController get sos => widget.sos;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _press(BuildContext context) async {
    if (sos.sending) return;
    final messenger = ScaffoldMessenger.of(context);
    final msg = _msg.text.trim();
    final ok = await sos.sendSos(body: msg.isEmpty ? null : msg);
    final active = sos.active;
    final via = active?.status;
    final label = !ok
        ? 'SOS failed — no LoRa/BLE/Online link'
        : switch (via) {
            SosState.loraSent => 'SOS sent over LoRa',
            SosState.bleSent => 'SOS sent over BLE',
            SosState.onlineSent => 'SOS sent over Online',
            _ => 'SOS sent',
          };
    messenger.showSnackBar(SnackBar(
      content: Text(label),
      backgroundColor: ok ? Nepali.green : Nepali.crimsonDark,
    ));
    if (ok) _msg.clear();
  }

  @override
  Widget build(BuildContext context) {
    final sending = sos.sending;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: Column(
        children: [
          GestureDetector(
        onTap: () => _press(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: sending
                  ? [Nepali.gold, Nepali.crimson]
                  : [Nepali.crimson, Nepali.crimsonDark],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Nepali.gold,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (sending ? Nepali.gold : Nepali.crimson)
                    .withValues(alpha: 0.5),
                blurRadius: 32,
                spreadRadius: 3,
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (sending)
                      const SizedBox(
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 4,
                        ),
                      )
                    else
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                        child: const Center(
                          child: Text('SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              )),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      sending ? 'SENDING SOS…' : 'PRESS FOR SOS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'उद्धार चाहिन्छ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
          const SizedBox(height: 12),
          TextField(
            controller: _msg,
            maxLength: 200,
            style: const TextStyle(color: Nepali.snow, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Add a message for the rescue team (optional)',
              hintStyle: const TextStyle(color: Nepali.muted),
              counterText: '',
              filled: true,
              fillColor: Nepali.panel,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Nepali.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Nepali.gold),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}


class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.ble,
    required this.gps,
    required this.sos,
    required this.link,
  });
  final BleRelayConnection ble;
  final GpsService gps;
  final SosController sos;
  final LinkController link;

  @override
  Widget build(BuildContext context) {
    final net = ble.state.value;
    final online = link.onlineReachable;
    final rising = switch (net) {
      BleLinkState.off => online,
      BleLinkState.error => online,
      _ => false,
    };
    final netLabel = switch (net) {
      BleLinkState.off when online => 'Online',
      BleLinkState.error when online => 'Online',
      // Relay-only mode with no link yet is not "unavailable": we are actively
      // looking for N-A, and saying otherwise sent us chasing a hardware fault
      // that did not exist.
      BleLinkState.off when link.huntingRelay => 'Searching for relay N-A…',
      BleLinkState.off => 'BLE unavailable',
      BleLinkState.scanning => 'Scanning for relay…',
      BleLinkState.connecting => 'Connecting to relay…',
      BleLinkState.connected => 'BLE · Relay connected',
      // Force-relay-hop on with no relay in range: still hunting, still
      // retrying. "BLE error" sent us debugging a fault that did not exist.
      BleLinkState.error when link.relayAbsent => 'Searching for relay N-A…',
      BleLinkState.error => 'BLE error',
    };
    final gpsLabel = switch (gps.status.value) {
      GpsStatus.ready =>
        'GPS available${gps.last != null ? ' (${gps.last!.latitude.toStringAsFixed(4)}, ${gps.last!.longitude.toStringAsFixed(4)})' : ''}',
      GpsStatus.locating => 'GPS locating…',
      GpsStatus.unavailable => 'GPS unavailable (indoor?)',
      GpsStatus.denied => 'GPS permission denied',
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
                rising ? Icons.public : Icons.bluetooth,
                netLabel,
                net == BleLinkState.connected
                    ? Nepali.risk2
                    : rising
                        ? Nepali.green
                        : Colors.grey,
                trailing: net == BleLinkState.connected && ble.rssi.value != null
                    ? '${ble.rssi.value} dBm'
                    : rising
                        ? link.serverUrl
                        : null),
            // A red "only the gateway is in range" line while we are still hunting for
            // N-A reads like a fault. It is expected in force-relay-hop mode.
            if (net == BleLinkState.error && ble.error.value != null)
              _row(
                link.relayAbsent ? Icons.info_outline : Icons.error_outline,
                '${ble.error.value}',
                link.relayAbsent ? Nepali.gold : Nepali.crimson,
              ),
            if (ble.missingCharacteristics.isNotEmpty)
              _row(
                Icons.warning_amber,
                'Node missing: ${ble.missingCharacteristics.join(', ')}',
                Nepali.crimson,
              ),
            const Divider(),
            _row(
              Icons.cell_tower,
              link.peerModeRunning
                  ? 'Phone relay ON · ${link.myNodeId}${link.peerConnected ? ' · peer linked' : ''}'
                  : 'Phone relay OFF',
              link.peerConnected
                  ? Nepali.green
                  : link.peerModeRunning
                      ? Nepali.gold
                      : Colors.grey,
            ),
            if (link.peerError != null)
              _row(Icons.warning_amber, link.peerError!, Nepali.crimson),
            if (link.relayHopNote != null)
              _row(Icons.alt_route, link.relayHopNote!, Nepali.gold),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: link.forceRelayHop,
              onChanged: (v) => link.setForceRelayHop(v),
              activeThumbColor: Nepali.green,
              title: const Text('Force relay hop',
                  style: TextStyle(color: Nepali.snow, fontSize: 14)),
              subtitle: Text(
                link.forceRelayHop
                    ? 'ON · gateway RCUE is skipped, SOS must go relay → LoRa'
                    : 'OFF · normal mode — the nearest node (relay or gateway) is used',
                style: const TextStyle(color: Nepali.muted, fontSize: 12),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: link.bleBusy
                        ? null
                        : () async {
                            await link.reconnectLink();
                            await link.refresh();
                          },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Nepali.snow,
                      side: const BorderSide(color: Nepali.line),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => link.refresh(),
                    icon: const Icon(Icons.cloud_sync, size: 18),
                    label: const Text('Refresh status'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Nepali.snow,
                      side: const BorderSide(color: Nepali.line),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            _row(Icons.gps_fixed, gpsLabel,
                gps.status.value == GpsStatus.ready ? Nepali.green : Colors.grey),
            const Divider(),
            _row(
              Icons.emergency,
              sos.sending
                  ? 'SOS Status: SENDING…'
                  : sos.active == null
                      ? 'SOS Status: READY'
                      : 'SOS Status: SENT — tap SOS again to send another',
              sos.sending ? Nepali.gold : Colors.lightGreenAccent,
              trailing: sos.active?.details,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, Color color, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Nepali.snow, fontSize: 14))),
          if (trailing != null)
            Text(trailing,
                style: const TextStyle(color: Nepali.muted, fontSize: 12),
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({required this.alerts, required this.ble});
  final AlertController alerts;
  final BleRelayConnection ble;

  @override
  Widget build(BuildContext context) {
    final latest = alerts.alerts.firstWhere((a) => !a.acknowledged);
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Nepali.panel,
        builder: (_) => _AlertDetail(alert: latest, ble: ble),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Nepali.crimson, Nepali.crimsonDark]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Nepali.gold, width: 1.4),
          boxShadow: [
            BoxShadow(
                color: Nepali.crimson.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: 1),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Nepali.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                latest.title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.alerts, required this.ble});
  final AlertController alerts;
  final BleRelayConnection ble;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(
          title: 'EMERGENCY MESSAGES',
          devanagari: 'आपतकालिन सन्देश',
        ),
        const SizedBox(height: 10),
        ...alerts.alerts.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: a.severity == Severity.critical
                        ? Nepali.crimson.withValues(alpha: 0.7)
                        : Nepali.gold.withValues(alpha: 0.6),
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    a.packet.type == 'BROAD'
                        ? Icons.campaign
                        : Icons.forum,
                    color: a.severity == Severity.critical
                        ? Nepali.crimson
                        : Nepali.gold,
                  ),
                  title: Text(a.title,
                      style: const TextStyle(
                          color: Nepali.snow, fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    a.packet.body.isEmpty ? '(no text)' : a.packet.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Nepali.muted),
                  ),
                  trailing: a.acknowledged
                      ? const Icon(Icons.check_circle, color: Nepali.green)
                      : IconButton(
                          icon: const Icon(Icons.thumb_up_alt_outlined,
                              color: Nepali.risk2),
                          tooltip: 'Acknowledge',
                          onPressed: () async {
                            await alerts.acknowledge(a, sender: ble.sendAck);
                          },
                        ),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: Nepali.panel,
                    builder: (_) => _AlertDetail(alert: a, ble: ble),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.devanagari});
  final String title;
  final String devanagari;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Nepali.crimson,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(title,
            style: const TextStyle(
                color: Nepali.snow,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(devanagari,
            style: const TextStyle(
                color: Nepali.muted, fontSize: 11, letterSpacing: 0.4)),
      ],
    );
  }
}

class _AlertDetail extends StatelessWidget {
  const _AlertDetail({required this.alert, required this.ble});
  final EmergencyAlert alert;
  final BleRelayConnection ble;

  @override
  Widget build(BuildContext context) {
    final p = alert.packet;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    color: p.prio >= 2 ? Nepali.crimson : Nepali.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const Spacer(),
                Text(alert.severity.label.toUpperCase(),
                    style: TextStyle(
                      color: p.prio >= 2 ? Nepali.crimson : Nepali.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            _detail('Message', p.body.isEmpty ? '(no text)' : p.body),
            _detail('Source', p.src ?? '-'),
            _detail(
                'Timestamp',
                DateTime.fromMillisecondsSinceEpoch(p.ts * 1000)
                    .toLocal()
                    .toString()
                    .substring(0, 19)),
            if (p.path.isNotEmpty) _detail('Path', p.path.join(' → ')),
            _detail('Affected area', p.body), // area is encoded inside broadcast body
            const SizedBox(height: 16),
            if (!alert.acknowledged)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Nepali.green,
                      foregroundColor: const Color(0xFF052E1C),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.thumb_up_alt_outlined),
                  label: const Text('ACKNOWLEDGE RECEIVED'),
                  onPressed: () async {
                    await context
                        .read<AlertController>()
                        .acknowledge(alert, sender: ble.sendAck);
                  },
                ),
              )
            else
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Nepali.green),
                  SizedBox(width: 8),
                  Text('Acknowledged',
                      style: TextStyle(color: Nepali.green)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: Nepali.muted, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: Nepali.snow, fontSize: 15)),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.sos});
  final SosController sos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(title: 'SOS HISTORY', devanagari: 'सोस इतिहास'),
        const SizedBox(height: 10),
        ...sos.messages.take(6).map((m) {
          final color = switch (m.status) {
            SosState.acknowledged => Nepali.green,
            SosState.received ||
            SosState.loraSent ||
            SosState.relayed =>
              Nepali.risk2,
            SosState.onlineSent => Nepali.gold,
            SosState.failed || SosState.expired => Nepali.risk0,
            _ => Nepali.gold,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              dense: true,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Icon(Icons.sos, color: color, size: 18),
              ),
              title: Text('${m.packet.mid} · ${m.status.label}',
                  style: const TextStyle(
                      color: Nepali.snow,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              subtitle: Text(m.details ?? '',
                  style: const TextStyle(color: Nepali.muted, fontSize: 11)),
              trailing: Text(m.packet.src ?? '',
                  style: const TextStyle(color: Nepali.muted, fontSize: 12)),
            ),
          );
        }),
      ],
    );
  }
}

/// Collapsible line-by-line dispatch log — lets a field user report exactly
/// what the radio/BLE stack is doing (scan visibility, advertising, peers).
class _DebugSection extends StatelessWidget {
  const _DebugSection({required this.log});
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    if (log.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: const Icon(Icons.bug_report, color: Nepali.gold, size: 20),
          title: const Text('DEBUG LOG',
              style: TextStyle(
                  color: Nepali.snow, fontSize: 12, fontWeight: FontWeight.w700)),
          children: [
            if (log.isEmpty)
              const Text('(empty)',
                  style: TextStyle(color: Nepali.muted, fontSize: 12))
            else
              ...log.map((line) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.split('  ').first + '  ',
                            style: const TextStyle(
                                color: Nepali.muted,
                                fontSize: 11,
                                fontFamily: 'monospace')),
                        Expanded(
                          child: Text(
                              line.split('  ').length > 1
                                  ? line.split('  ').sublist(1).join('  ')
                                  : '',
                              style: const TextStyle(
                                  color: Nepali.snow,
                                  fontSize: 11,
                                  fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}