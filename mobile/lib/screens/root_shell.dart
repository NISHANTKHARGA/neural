import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_store.dart';
import '../theme/nepali.dart';
import 'contacts_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

/// Bottom-nav shell: Home (real SOS), Emergency contacts, Profile.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    ContactsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Nepali.night,
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Nepali.panel,
        indicatorColor: Nepali.crimsonSoft,
        surfaceTintColor: Colors.transparent,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sos_outlined),
            selectedIcon: Icon(Icons.sos, color: Nepali.crimson),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts, color: Nepali.crimson),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Nepali.crimson),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Chooses between the login page and the app shell once the stored session has
/// been read.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionStore>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SessionStore>();
    if (!store.loaded) {
      return const Scaffold(
        backgroundColor: Nepali.night,
        body: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: Nepali.crimson),
          ),
        ),
      );
    }
    return store.loggedIn ? const RootShell() : const LoginScreen();
  }
}