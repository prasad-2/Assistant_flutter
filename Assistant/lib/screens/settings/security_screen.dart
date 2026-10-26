// App lock settings: on/off, method (device biometrics / app PIN + biometrics /
// app PIN only), PIN change and the auto-lock delay.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../lock_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  AuthService get _auth => context.read<AppState>().auth;

  Future<String?> _askPassword() async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? err;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Set password / PIN'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: a,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'New password / PIN')),
            const SizedBox(height: 12),
            TextField(
                controller: b,
                obscureText: true,
                decoration:
                    InputDecoration(labelText: 'Confirm', errorText: err)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (a.text.length < 4) {
                  setS(() => err = 'Use at least 4 characters');
                } else if (a.text != b.text) {
                  setS(() => err = 'Does not match');
                } else {
                  Navigator.pop(ctx, a.text);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Switches to [method] ('device' | 'password' | 'pin_only'); true on success.
  Future<bool> _activate(String method) async {
    if (method == 'device') {
      if (!await _auth.deviceSupported()) {
        if (mounted) {
          showErrorDialog(context,
              'No screen lock / biometric is set up on this phone. Set one in system settings first, or use an app PIN / password.');
        }
        return false;
      }
      if (!await _auth.deviceAuth('Confirm to enable app lock')) return false;
    } else if (!_auth.hasPassword) {
      final pw = await _askPassword();
      if (pw == null) return false;
      await _auth.setPassword(pw);
    }
    await _auth.setMethod(method);
    await _auth.setEnabled(true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final enabled = _auth.enabled;
    final method = _auth.method;
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: ListView(children: [
        SwitchListTile(
          title: const Text('Require authentication'),
          subtitle:
              const Text('Needed to open the app, take a backup or restore'),
          value: enabled,
          onChanged: (v) async {
            if (v) {
              final ok = await _activate(
                  _auth.usesPassword && _auth.hasPassword ? method : 'device');
              if (ok) setState(() {});
            } else {
              if (!await requireAuth(context, _auth)) return;
              await _auth.setEnabled(false);
              setState(() {});
            }
          },
        ),
        if (enabled) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Method'),
          ),
          RadioListTile<String>(
            title: const Text('Biometrics / device lock'),
            subtitle: const Text(
                'Fingerprint, face unlock, or the phone\'s PIN / pattern / password'),
            value: 'device',
            groupValue: method,
            onChanged: (v) async {
              if (!await requireAuth(context, _auth)) return;
              if (await _activate('device')) setState(() {});
            },
          ),
          RadioListTile<String>(
            title: const Text('App PIN / password + biometrics'),
            subtitle: const Text(
                'Own PIN or password; biometrics available as a shortcut'),
            value: 'password',
            groupValue: method,
            onChanged: (v) async {
              if (!await requireAuth(context, _auth)) return;
              if (await _activate('password')) setState(() {});
            },
          ),
          RadioListTile<String>(
            title: const Text('App PIN / password only'),
            subtitle: const Text(
                'No system biometrics. Only the app\'s own PIN or password. It cannot be recovered if forgotten.'),
            value: 'pin_only',
            groupValue: method,
            onChanged: (v) async {
              if (!await requireAuth(context, _auth)) return;
              if (await _activate('pin_only')) setState(() {});
            },
          ),
          // how long the app may stay in the background before it re-locks
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<int>(
              value: _auth.lockDelay.inSeconds,
              decoration: const InputDecoration(
                  labelText: 'Lock again after leaving the app'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Immediately')),
                DropdownMenuItem(value: 30, child: Text('After 30 seconds')),
                DropdownMenuItem(value: 60, child: Text('After 1 minute')),
                DropdownMenuItem(value: 300, child: Text('After 5 minutes')),
              ],
              onChanged: (v) async {
                await _auth.setLockDelaySeconds(v ?? 0);
                setState(() {});
              },
            ),
          ),
          if (_auth.usesPassword)
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Change PIN / password'),
              onTap: () async {
                if (!await requireAuth(context, _auth)) return;
                final pw = await _askPassword();
                if (pw != null) {
                  await _auth.setPassword(pw);
                  if (mounted) snack(context, 'PIN / password updated');
                }
              },
            ),
        ],
      ]),
    );
  }
}
