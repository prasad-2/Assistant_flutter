// App lock logic: settings, password hashing and the system biometric prompt.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tells the auto-lock that the app is *temporarily* leaving the foreground
/// because of something WE started (file picker, biometric prompt, permission
/// dialog). Without this, the app would lock itself right after such dialogs.
class LockGuard {
  static int _busy = 0;
  static DateTime _until = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while a guarded operation runs (plus 2 s after it ends, because the
  /// "resumed" lifecycle event can arrive slightly later).
  static bool get isBusy => _busy > 0 || DateTime.now().isBefore(_until);

  /// Runs [action] while the auto-lock is suspended.
  static Future<T> run<T>(Future<T> Function() action) async {
    _busy++;
    try {
      return await action();
    } finally {
      _busy--;
      _until = DateTime.now().add(const Duration(seconds: 2));
    }
  }
}

/// App lock settings + verification.
///
/// Methods (`lock_method`):
///   * `device`   – system biometrics / face / phone PIN, pattern, password
///   * `password` – app PIN/password, with the biometric prompt as a shortcut
///   * `pin_only` – app PIN/password ONLY (system biometrics never used)
///
/// The same class also powers the separate FINANCE lock: it is created with
/// another [prefix] ('fin_lock'), so its settings and its PIN / password are
/// stored under different keys and are independent from the app lock.
class AuthService {
  AuthService(this.prefs, {this.prefix = 'lock'});
  final SharedPreferences prefs;

  /// Key prefix: 'lock' = app lock, 'fin_lock' = finance lock.
  final String prefix;
  final LocalAuthentication _la = LocalAuthentication();

  bool get enabled => prefs.getBool('${prefix}_enabled') ?? false;
  String get method => prefs.getString('${prefix}_method') ?? 'device';

  /// True for both methods that use the app's own PIN / password.
  bool get usesPassword => method == 'password' || method == 'pin_only';
  bool get hasPassword => prefs.getString('${prefix}_hash') != null;

  /// How long the app may stay in the background before it locks again.
  Duration get lockDelay => Duration(seconds: prefs.getInt('${prefix}_delay') ?? 0);

  Future<void> setEnabled(bool v) => prefs.setBool('${prefix}_enabled', v);
  Future<void> setMethod(String m) => prefs.setString('${prefix}_method', m);
  Future<void> setLockDelaySeconds(int s) => prefs.setInt('${prefix}_delay', s);

  /// Whether the phone has a screen lock / biometric that can be used.
  Future<bool> deviceSupported() async {
    try {
      return await _la.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Shows the system authentication prompt (biometric or device PIN).
  Future<bool> deviceAuth(String reason) {
    return LockGuard.run(() async {
      try {
        return await _la.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
              biometricOnly: false, stickyAuth: true),
        );
      } catch (_) {
        return false;
      }
    });
  }

  String _hash(String salt, String pw) =>
      sha256.convert(utf8.encode('$salt:$pw')).toString();

  /// Stores a salted SHA-256 hash of the password (never the password).
  Future<void> setPassword(String pw) async {
    final rnd = Random.secure();
    final salt =
        base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await prefs.setString('${prefix}_salt', salt);
    await prefs.setString('${prefix}_hash', _hash(salt, pw));
  }

  bool verifyPassword(String pw) {
    final salt = prefs.getString('${prefix}_salt');
    final h = prefs.getString('${prefix}_hash');
    if (salt == null || h == null) return false;
    return _hash(salt, pw) == h;
  }
}
