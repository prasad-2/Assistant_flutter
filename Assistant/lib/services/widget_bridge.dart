// Talks to native Android code (MainActivity / widget provider).
import 'package:flutter/services.dart';

class WidgetBridge {
  static const _channel = MethodChannel('com.personal.my_finance_todo/widget');

  /// Asks Android to redraw all Assistant widgets (theme / data changed).
  /// Errors are ignored: the widget only exists on Android.
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }

  /// Turns FLAG_SECURE on/off: hides the app in the recent-apps list and
  /// blocks screenshots (like WhatsApp does with its screen lock).
  static Future<void> setSecure(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', on);
    } catch (_) {}
  }
}
