package com.personal.my_finance_todo

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity. It extends FlutterFragmentActivity because the local_auth
 * plugin (biometrics) requires it.
 *
 * It also exposes a tiny channel so the Dart side can ask the home-screen
 * widget to redraw itself (e.g. after the user changed the app theme).
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.personal.my_finance_todo/widget"
        ).setMethodCallHandler { call, result ->
            if (call.method == "refresh") {
                MyAppWidgetProvider.refreshAll(applicationContext)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
