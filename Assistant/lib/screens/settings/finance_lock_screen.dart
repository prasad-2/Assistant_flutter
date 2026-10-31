// Settings → Finance lock: asks for authentication before the Finance section
// opens. Independent from the app lock: it has its own on/off switch, its own
// method and (for the PIN method) its own PIN / password, which must differ
// from the app lock's PIN / password.
//
// Methods (stored by AuthService with the prefix 'fin_lock'):
//   * device   – biometrics / face / the phone's own screen lock
//   * pin_only – a separate PIN or password just for Finance
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../lock_screen.dart';

class FinanceLockScreen extends StatefulWidget {
  const FinanceLockScreen({super.key});
  @override
  State<FinanceLockScreen> createState() => _FinanceLockScreenState();
}

class _FinanceLockScreenState extends State<FinanceLockScreen> {
  AuthService get _fin => context.read<AppState>().financeAuth;
  AuthService get _app => context.read<AppState>().auth;

  /// Asks for a new PIN / password twice. Rejects the app lock's PIN.
  Future<String?> _askPassword() async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? err;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Finance PIN / password'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: a,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'New PIN / password')),
            const SizedBox(height: 12),
            TextField(
                controller: b,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Confirm', errorText: err)),
            const SizedBox(height: 8),
            Text('It must be different from your app lock PIN / password.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (a.text.length < 4) {
                  setS(() => err = 'Use at least 4 characters');
                } else if (a.text != b.text) {
                  setS(() => err = 'Does not match');
                } else if (_app.hasPassword && _app.verifyPassword(a.text)) {
                  setS(() => err = 'Use a different PIN than the app lock');
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

  /// Switches the finance lock to [method] and turns it on; true on success.
  Future<bool> _activate(String method) async {
    if (method == 'device') {
      if (!await _fin.deviceSupported()) {
        if (mounted) {
          showErrorDialog(context,
              'No screen lock / biometric is set up on this phone. Set one in system settings first, or use a separate PIN.');
        }
        return false;
      }
      if (!await _fin.deviceAuth('Confirm to lock Finance')) return false;
    } else if (!_fin.hasPassword) {
      final pw = await _askPassword();
      if (pw == null) return false;
      await _fin.setPassword(pw);
    }
    await _fin.setMethod(method);
    await _fin.setEnabled(true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final enabled = _fin.enabled;
    final method = _fin.method == 'device' ? 'device' : 'pin_only';
    return Scaffold(
      appBar: AppBar(title: const Text('Finance lock')),
      body: ListView(children: [
        SwitchListTile(
          title: const Text('Lock the Finance section'),
          subtitle: const Text(
              'Authentication is asked once each time the app is opened'),
          value: enabled,
          onChanged: (v) async {
            if (v) {
              if (await _activate(method)) setState(() {});
            } else {
              if (!await requireAuth(context, _fin, title: 'Finance lock')) return;
              await _fin.setEnabled(false);
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
            subtitle: const Text('Fingerprint, face unlock or the phone\'s PIN / pattern'),
            value: 'device',
            groupValue: method,
            onChanged: (v) async {
              if (!await requireAuth(context, _fin, title: 'Finance lock')) return;
              if (await _activate('device')) setState(() {});
            },
          ),
          RadioListTile<String>(
            title: const Text('Separate PIN / password'),
            subtitle: const Text(
                'Its own PIN just for Finance (different from the app lock). It cannot be recovered if forgotten.'),
            value: 'pin_only',
            groupValue: method,
            onChanged: (v) async {
              if (!await requireAuth(context, _fin, title: 'Finance lock')) return;
              if (await _activate('pin_only')) setState(() {});
            },
          ),
          if (method == 'pin_only')
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Change Finance PIN / password'),
              onTap: () async {
                if (!await requireAuth(context, _fin, title: 'Finance lock')) return;
                final pw = await _askPassword();
                if (pw != null) {
                  await _fin.setPassword(pw);
                  if (mounted) snack(context, 'Finance PIN updated');
                }
              },
            ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
              'Once unlocked, Finance stays open until you close the app; opening the app again asks for authentication again. Other places that show account figures (Home cards, charts, the widget) are not covered by this lock.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }
}
