// Talks to the native Android home-screen widget.
import 'package:flutter/services.dart';

class WidgetBridge {
  static const _channel = MethodChannel('com.personal.my_finance_todo/widget');

  /// Asks Android to redraw all Assistant widgets (e.g. after a theme change).
  /// Errors are ignored: the widget only exists on Android.
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }
}
