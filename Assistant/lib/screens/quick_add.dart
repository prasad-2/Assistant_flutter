// "Quick add" screen opened by the home-screen widget.
//
// The native QuickAddActivity (transparent) runs this Flutter entry point. It
// shows only a dialog containing the normal add-transaction or add-todo form
// on top of the user's home screen, so the full app never opens.
// If the app lock is enabled the lock screen is shown first.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_init.dart';
import '../main.dart' show buildTheme, kAppName;
import '../providers/app_state.dart';
import '../widgets/app_lock_layer.dart';
import '../widgets/common.dart';
import 'finance/transaction_form.dart';
import 'todo/todo_form.dart';

/// Channel implemented by QuickAddActivity.kt.
const _channel = MethodChannel('com.personal.my_finance_todo/quickadd');

/// Closes the transparent activity (falls back to SystemNavigator).
Future<void> _closeActivity() async {
  try {
    await _channel.invokeMethod<void>('close');
  } catch (_) {
    await SystemNavigator.pop();
  }
}

class QuickAddApp extends StatefulWidget {
  const QuickAddApp({super.key});
  @override
  State<QuickAddApp> createState() => _QuickAddAppState();
}

class _QuickAddAppState extends State<QuickAddApp> {
  late final Future<AppState> _future = initApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          // transparent while loading (or failed): close if it failed
          if (snap.hasError) WidgetsBinding.instance.addPostFrameCallback((_) => _closeActivity());
          return const SizedBox.shrink();
        }
        final state = snap.data!;
        return ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            title: kAppName,
            debugShowCheckedModeBanner: false,
            themeMode: state.themeMode,
            theme: buildTheme(Brightness.light, state.lightSeedColor),
            darkTheme: buildTheme(Brightness.dark, state.darkSeedColor),
            builder: (context, child) => AppLockLayer(child: child!),
            home: const _QuickAddHome(),
          ),
        );
      },
    );
  }
}

/// Transparent page that immediately opens the dialog.
class _QuickAddHome extends StatefulWidget {
  const _QuickAddHome();
  @override
  State<_QuickAddHome> createState() => _QuickAddHomeState();
}

class _QuickAddHomeState extends State<_QuickAddHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    // which button of the widget was tapped: "transaction" or "todo"
    String mode = 'transaction';
    try {
      mode = await _channel.invokeMethod<String>('getMode') ?? 'transaction';
    } catch (_) {}
    if (!mounted) return;

    final st = context.read<AppState>();
    if (mode == 'transaction' && st.accounts.isEmpty) {
      await showErrorDialog(context, 'Add a bank account in the app first.');
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .86,
            child: mode == 'todo' ? const TodoFormPage() : const TransactionFormPage(),
          ),
        ),
      );
    }
    // dialog dismissed (saved or cancelled): remove the transparent activity
    await _closeActivity();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Colors.transparent);
}
