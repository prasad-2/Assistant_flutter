package com.personal.my_finance_todo

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Transparent activity started by the home-screen widget buttons.
 *
 * It runs the Dart function `quickAddMain` (lib/main.dart) which shows only an
 * "add transaction / add todo" dialog above the launcher, so the full app UI
 * never opens. The theme (QuickAddTheme) and the "background_mode=transparent"
 * intent extra (set by the widget) make the window see-through.
 */
class QuickAddActivity : FlutterFragmentActivity() {

    /** Use the second Dart entry point instead of main(). */
    override fun getDartEntrypointFunctionName(): String = "quickAddMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // lets Dart redraw the home-screen widget after a save
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.personal.my_finance_todo/quickadd"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // which widget button was tapped: "transaction" or "todo"
                "getMode" -> result.success(intent.getStringExtra("mode") ?: "transaction")
                // Dart finished (saved or cancelled): remove this activity
                "close" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }
}
