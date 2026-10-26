// Covers the WHOLE app (all routes) with the lock screen:
//   * at cold start when the lock is enabled
//   * whenever the app comes back from the background after the configured
//     delay – this is what makes "back button, then reopen" ask for
//     authentication again.
// It also refreshes data when the app returns to the foreground, because the
// home-screen widget may have added transactions / todos meanwhile.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../screens/lock_screen.dart';
import '../services/auth_service.dart';

class AppLockLayer extends StatefulWidget {
  final Widget child; // the Navigator built by MaterialApp
  const AppLockLayer({super.key, required this.child});
  @override
  State<AppLockLayer> createState() => _AppLockLayerState();
}

class _AppLockLayerState extends State<AppLockLayer>
    with WidgetsBindingObserver {
  late bool _locked;
  Key _lockKey = UniqueKey(); // new key => fresh lock screen (re-prompts)
  DateTime? _leftAt; // when the app went to the background

  AuthService get _auth => context.read<AppState>().auth;

  @override
  void initState() {
    super.initState();
    _locked = _auth.enabled; // locked right at start-up
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Ignore pauses caused by our own dialogs (file picker, biometric...).
      _leftAt = LockGuard.isBusy ? null : DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      context.read<AppState>().refreshAll();
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          _auth.enabled &&
          !_locked &&
          DateTime.now().difference(left) >= _auth.lockDelay) {
        setState(() {
          _locked = true;
          _lockKey = UniqueKey();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_locked)
        // Own Overlay: text fields need one and we live outside the Navigator.
        Positioned.fill(
          child: Overlay(
            key: _lockKey,
            initialEntries: [
              OverlayEntry(
                builder: (_) => LockScreen(
                  auth: _auth,
                  onUnlocked: () => setState(() => _locked = false),
                ),
              ),
            ],
          ),
        ),
    ]);
  }
}
