import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/clipboard_controller.dart';
import '../controllers/settings_controller.dart';
import '../screens/devices_screen.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';

/// Adaptive navigation shell.
/// - Narrow (< 600 dp): bottom [NavigationBar].
/// - Wide (≥ 600 dp): left [NavigationRail].
///
/// Also the app's capture point: Android only permits a clipboard read while the
/// app holds focus, so this watches the lifecycle and captures on resume. That
/// is why the observer lives here, on the first screen behind the auth gate,
/// rather than in a background service — no such service is permitted to read
/// the clipboard on modern Android.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startUp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Settings load first: the clipboard rules (filters, Wi-Fi only) depend on
  /// them, and capturing before they arrive would ignore the user's choices.
  Future<void> _startUp() async {
    if (!mounted) return;
    await context.read<SettingsController>().load();
    if (!mounted) return;
    await context.read<ClipboardController>().start();
    if (!mounted) return;
    await _captureClipboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _captureClipboard();
  }

  Future<void> _captureClipboard() async {
    final clipboard = context.read<ClipboardController>();
    final saved = await clipboard.captureFromDevice();
    if (!mounted || saved == null) return;

    final alerts = context.read<SettingsController>().settings?.syncAlerts;
    if (alerts ?? false) {
      // Says that something was saved without repeating what it was — a toast
      // showing clipboard content is a shoulder-surfing gift.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to CopyOnce')));
    }
  }

  void _goToDevices() => setState(() => _index = 1);

  Widget get _currentScreen => switch (_index) {
    0 => HomeScreen(onViewDevices: _goToDevices),
    1 => const DevicesScreen(),
    2 => const SettingsScreen(),
    _ => HomeScreen(onViewDevices: _goToDevices),
  };

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.content_paste_outlined),
      selectedIcon: Icon(Icons.content_paste_rounded),
      label: 'Clipboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.devices_outlined),
      selectedIcon: Icon(Icons.devices_rounded),
      label: 'Devices',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.content_paste_outlined),
      selectedIcon: Icon(Icons.content_paste_rounded),
      label: Text('Clipboard'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.devices_outlined),
      selectedIcon: Icon(Icons.devices_rounded),
      label: Text('Devices'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('Settings'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return _WideLayout(
            index: _index,
            onIndexChanged: (i) => setState(() => _index = i),
            destinations: _railDestinations,
            screen: _currentScreen,
          );
        }
        return _NarrowLayout(
          index: _index,
          onIndexChanged: (i) => setState(() => _index = i),
          destinations: _destinations,
          screen: _currentScreen,
        );
      },
    );
  }
}

// ── Layout variants ────────────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.index,
    required this.onIndexChanged,
    required this.destinations,
    required this.screen,
  });

  final int index;
  final ValueChanged<int> onIndexChanged;
  final List<NavigationDestination> destinations;
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screen,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: onIndexChanged,
            destinations: destinations,
          ),
        ],
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.index,
    required this.onIndexChanged,
    required this.destinations,
    required this.screen,
  });

  final int index;
  final ValueChanged<int> onIndexChanged;
  final List<NavigationRailDestination> destinations;
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left rail
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onIndexChanged,
                  destinations: destinations,
                  labelType: NavigationRailLabelType.all,
                  leading: const SizedBox(height: 24),
                ),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          // Content
          Expanded(child: screen),
        ],
      ),
    );
  }
}
