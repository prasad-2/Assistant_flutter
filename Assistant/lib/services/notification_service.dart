// Alarm-style local reminders for todos (works fully offline).
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'auth_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _askedExact = false;
  bool _askedNotif = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Silent initialisation. It never shows a dialog, so it is safe at start-up.
  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Asks for the notification permission (Android 13+). Call it only after
  /// the first frame is visible.
  Future<void> requestNotificationPermission() async {
    if (!_ready || _askedNotif) return;
    _askedNotif = true;
    try {
      await LockGuard.run(() async => _android?.requestNotificationsPermission());
    } catch (e) {
      debugPrint('Notification permission failed: $e');
    }
  }

  /// Opens the "Alarms & reminders" settings page when exact alarms are not
  /// allowed yet. Call it from a user action (saving a todo with a reminder).
  Future<void> askExactAlarmPermissionIfNeeded() async {
    if (!_ready || _askedExact) return;
    try {
      final ok = await _android?.canScheduleExactNotifications() ?? true;
      if (!ok) {
        _askedExact = true;
        await LockGuard.run(() async => _android?.requestExactAlarmsPermission());
      }
    } catch (e) {
      debugPrint('Exact alarm permission failed: $e');
    }
  }

  /// Schedules a one-off alarm notification at [when] (ignored if in the past).
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_ready || !when.isAfter(DateTime.now())) return;
    try {
      // exact alarms when allowed, otherwise the system may delay slightly
      final exact = await _android?.canScheduleExactNotifications() ?? false;
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'todo_reminders',
          'Todo reminders',
          channelDescription: 'Alarm-style reminders for your todos',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          ticker: 'Todo reminder',
        ),
      );
      // A one-off alarm only needs the absolute instant, so UTC is enough.
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.UTC),
        details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Schedule failed: $e');
    }
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
