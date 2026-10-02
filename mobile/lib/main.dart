import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ble/ble_relay_connection.dart';
import 'gps/gps_service.dart';
import 'link/link_controller.dart';
import 'screens/home_screen.dart';
import 'state/alert_controller.dart';
import 'state/sos_controller.dart';
import 'theme/nepali.dart';

void main() {
  runApp(const SafetrailsApp());
}

/// Requests Bluetooth/Location permissions automatically the moment the app
/// opens (first frame), before the user touches anything.
class _PermissionGate extends StatefulWidget {
  const _PermissionGate({required this.child});
  final Widget child;

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LinkController>().startupPermissions();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SafetrailsApp extends StatelessWidget {
  const SafetrailsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<GpsService>(create: (_) => GpsService()),
        Provider<BleRelayConnection>(create: (_) => BleRelayConnection()),
        ChangeNotifierProvider<LinkController>(
          create: (ctx) {
            final link = LinkController(relay: ctx.read<BleRelayConnection>());
            link.start();
            return link;
          },
        ),
        ChangeNotifierProvider<SosController>(
          create: (ctx) {
            final relay = ctx.read<BleRelayConnection>();
            final gps = ctx.read<GpsService>();
            final link = ctx.read<LinkController>();
            final c = SosController(relay: relay, gps: gps, link: link);
            c.watchInbound(relay.packets);
            return c;
          },
        ),
        ChangeNotifierProvider<AlertController>(
          create: (ctx) {
            final c = AlertController();
            ctx.read<BleRelayConnection>().packets.listen(c.absorb);
            return c;
          },
        ),
      ],
      child: MaterialApp(
        title: 'SAFETRAILS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: Nepali.night,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Nepali.crimson,
            brightness: Brightness.dark,
            primary: Nepali.crimson,
            secondary: Nepali.gold,
            surface: Nepali.panel,
          ),
          cardTheme: CardThemeData(
            color: Nepali.panel,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Nepali.line),
            ),
          ),
          dividerTheme: const DividerThemeData(color: Nepali.line),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        home: const HomeScreen(),
        builder: (context, child) =>
            _PermissionGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}