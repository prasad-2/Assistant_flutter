// Bottom navigation: Home | Finance | Todo | Settings.
// IndexedStack keeps each tab alive so scroll positions / state are preserved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        HomeScreen(onSeeAllTodos: () => setState(() => _i = 2)),
        const FinanceScreen(),
        const TodoScreen(),
        const SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
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
