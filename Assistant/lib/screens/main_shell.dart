// Bottom navigation: Home | Finance | Todo | Settings.
// IndexedStack keeps each tab alive so scroll positions / state are preserved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'lock_screen.dart';

import 'finance/finance_screen.dart';
import 'home_screen.dart';
import 'settings/settings_screen.dart';
import 'todo/todo_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _i = 0; // selected tab (0 = Home); the app still starts on Home

  /// Finance lock: becomes true when the user authenticates for the Finance
  /// section and STAYS true until the app is closed. Because it lives only in
  /// this State, closing the app and opening it again asks once more.
  bool _financeUnlocked = false;

  /// Bottom navigation.
  void _select(int v) => setState(() => _i = v);

  /// The Finance tab. When the finance lock is enabled and the user has not
  /// authenticated yet, an inline lock screen replaces the section. It is only
  /// created while the tab is selected (no hidden prompts at app start).
  Widget _financeTab() {
    final auth = context.read<AppState>().financeAuth;
    if (!auth.enabled || _financeUnlocked) return const FinanceScreen();
    if (_i != 1) return const SizedBox.shrink();
    return LockScreen(
      auth: auth,
      title: 'Finance is locked',
      reason: 'Unlock Finance',
      autoPrompt: false,
      onUnlocked: () => setState(() => _financeUnlocked = true),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Back button on the main screen: ask before closing the app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final exit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.exit_to_app),
            title: const Text('Close the app?'),
            content: const Text('Do you want to exit Assistant?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Stay')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Exit')),
            ],
          ),
        );
        if (exit == true) SystemNavigator.pop();
      },
      child: Scaffold(
      body: IndexedStack(index: _i, children: [
        HomeScreen(onSeeAllTodos: () => _select(2)),
        _financeTab(),
        const TodoScreen(),
        const SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Finance'),
          NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist),
              label: 'Todo'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    ));
  }
}
