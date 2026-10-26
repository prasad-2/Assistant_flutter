// Full-screen lock UI: system biometric prompt and/or the app's own PIN.
import 'package:flutter/material.dart';

import '../main.dart' show kAppName;
import '../services/auth_service.dart';

class LockScreen extends StatefulWidget {
  final AuthService auth;
  final VoidCallback onUnlocked; // called after successful authentication
  final bool cancellable; // true when pushed as a route (backup, settings)
  const LockScreen(
      {super.key,
      required this.auth,
      required this.onUnlocked,
      this.cancellable = false});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  String? _error;
  bool _supported = false; // phone has a screen lock / biometrics
  bool _obscure = true;

  /// True when the app's own PIN/password is the primary method.
  bool get _usePassword => widget.auth.usesPassword && widget.auth.hasPassword;

  /// The biometric shortcut is hidden for the "PIN only" method.
  bool get _showBiometricShortcut =>
      _supported && widget.auth.method == 'password';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final sup = await widget.auth.deviceSupported();
    if (!mounted) return;
    setState(() => _supported = sup);
    if (!_usePassword) {
      if (!sup) {
        // The phone no longer has a screen lock: do not lock the user out.
        widget.onUnlocked();
        return;
      }
      _deviceAuth(); // device method: prompt immediately
    } else if (_showBiometricShortcut) {
      _deviceAuth(); // password + biometrics: try the shortcut first
    }
  }

  Future<void> _deviceAuth() async {
    final ok = await widget.auth.deviceAuth('Unlock $kAppName');
    if (ok && mounted) widget.onUnlocked();
  }

  void _submit() {
    if (widget.auth.verifyPassword(_pw.text)) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Incorrect PIN / password');
      _pw.clear();
    }
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: widget.cancellable,
      child: Scaffold(
        // opaque: the app may use a transparent scaffold + background image
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_outline, size: 72, color: cs.primary),
                  const SizedBox(height: 16),
                  Text('$kAppName is locked',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  if (_usePassword) ...[
                    TextField(
                      controller: _pw,
                      obscureText: _obscure,
                      autofocus: true,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'PIN / password',
                        errorText: _error,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                            onPressed: _submit, child: const Text('Unlock'))),
                    if (_showBiometricShortcut)
                      TextButton.icon(
                        onPressed: _deviceAuth,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use biometrics / device lock'),
                      ),
                  ] else
                    FilledButton.icon(
                      onPressed: _deviceAuth,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Authenticate'),
                    ),
                  if (widget.cancellable)
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for authentication before a sensitive action (backup, restore,
/// changing lock settings). Returns true at once when the lock is disabled.
Future<bool> requireAuth(BuildContext context, AuthService auth) async {
  if (!auth.enabled) return true;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => LockScreen(
      auth: auth,
      cancellable: true,
      onUnlocked: () => Navigator.of(ctx).pop(true),
    ),
  ));
  return ok == true;
}
