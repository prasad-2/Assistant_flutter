// Dart side of the scheduled (automatic) backup. The real work (alarm, copying
// the database to the chosen folder) is native: see BackupSupport.kt.
import 'package:flutter/services.dart';

import 'auth_service.dart';

/// Snapshot of the backup schedule settings.
class BackupConfig {
  final bool enabled;
  final int intervalDays; // 1 = daily, 7 = weekly ...
  final int hour;
  final int minute;
  final int keep; // how many automatic backups to keep
  final String? folderName;
  final bool hasFolder;
  final DateTime? lastTime;
  final String? lastStatus;
  final DateTime? nextTime;

  const BackupConfig({
    required this.enabled,
    required this.intervalDays,
    required this.hour,
    required this.minute,
    required this.keep,
    required this.folderName,
    required this.hasFolder,
    required this.lastTime,
    required this.lastStatus,
    required this.nextTime,
  });

  static DateTime? _dt(Object? v) => (v is num && v > 0)
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
      : null;

  factory BackupConfig.fromMap(Map<Object?, Object?> m) => BackupConfig(
        enabled: m['enabled'] as bool,
        intervalDays: (m['intervalDays'] as num).toInt(),
        hour: (m['hour'] as num).toInt(),
        minute: (m['minute'] as num).toInt(),
        keep: (m['keep'] as num).toInt(),
        folderName: m['folderName'] as String?,
        hasFolder: m['hasFolder'] as bool,
        lastTime: _dt(m['lastTime']),
        lastStatus: m['lastStatus'] as String?,
        nextTime: _dt(m['nextTime']),
      );
}

class BackupSchedule {
  static const _ch = MethodChannel('com.personal.my_finance_todo/backup');

  static Future<BackupConfig> load() async => BackupConfig.fromMap(
      (await _ch.invokeMethod<Map<Object?, Object?>>('getConfig'))!);

  static Future<void> save({
    required bool enabled,
    required int intervalDays,
    required int hour,
    required int minute,
    required int keep,
  }) =>
      _ch.invokeMethod<void>('setConfig', {
        'enabled': enabled,
        'intervalDays': intervalDays,
        'hour': hour,
        'minute': minute,
        'keep': keep,
      });

  /// Opens the system folder picker. Returns the folder name or null.
  static Future<String?> pickFolder() =>
      LockGuard.run(() => _ch.invokeMethod<String>('pickFolder'));

  /// Runs a backup right now. Returns "OK: file" or "Failed: reason".
  static Future<String> runNow() async =>
      (await _ch.invokeMethod<String>('runNow')) ?? 'Failed';
}
