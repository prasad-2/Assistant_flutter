package com.personal.my_finance_todo

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity (FlutterFragmentActivity because local_auth needs it).
 *
 * Extra jobs:
 *  * FLAG_SECURE: hides the app in the recent-apps list / screenshots (like
 *    WhatsApp). Controlled by the "hide_in_recents" setting (default ON).
 *  * channel ".../widget": refresh the home-screen widget, toggle FLAG_SECURE
 *  * channel ".../backup": scheduled backup settings, folder picker, run now
 */
class MainActivity : FlutterFragmentActivity() {

    private var folderResult: MethodChannel.Result? = null

    /** System folder picker (Storage Access Framework) for the backup folder. */
    private val folderPicker =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val r = folderResult
            folderResult = null
            if (uri == null) {
                r?.success(null)
            } else {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    val name = BackupRunner.displayName(uri)
                    BackupPrefs.get(this).edit()
                        .putString("tree_uri", uri.toString())
                        .putString("tree_name", name)
                        .apply()
                    r?.success(name)
                } catch (e: Exception) {
                    r?.error("folder", e.message, null)
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Must be set before the first frame so the recents thumbnail is hidden.
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (flutterPrefs.getBoolean("flutter.hide_in_recents", true)) {
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onCreate(savedInstanceState)
        BackupScheduler.schedule(this) // keep the alarm armed (e.g. after an update)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "com.personal.my_finance_todo/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        MyAppWidgetProvider.refreshAll(applicationContext)
                        result.success(null)
                    }
                    "setSecure" -> {
                        val on = call.arguments as? Boolean ?: true
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, "com.personal.my_finance_todo/backup")
            .setMethodCallHandler { call, result ->
                val p = BackupPrefs.get(this)
                when (call.method) {
                    "getConfig" -> {
                        val enabled = p.getBoolean("enabled", false)
                        result.success(
                            mapOf(
                                "enabled" to enabled,
                                "intervalDays" to p.getInt("interval_days", 1),
                                "hour" to p.getInt("hour", 2),
                                "minute" to p.getInt("minute", 0),
                                "keep" to p.getInt("keep", 10),
                                "folderName" to p.getString("tree_name", null),
                                "hasFolder" to (p.getString("tree_uri", null) != null),
                                "lastTime" to p.getLong("last_time", 0L),
                                "lastStatus" to p.getString("last_status", null),
                                "nextTime" to
                                    if (enabled) BackupScheduler.nextTrigger(p, System.currentTimeMillis()) else 0L
                            )
                        )
                    }
                    "setConfig" -> {
                        val a = call.arguments as Map<*, *>
                        p.edit()
                            .putBoolean("enabled", a["enabled"] as Boolean)
                            .putInt("interval_days", (a["intervalDays"] as Number).toInt())
                            .putInt("hour", (a["hour"] as Number).toInt())
                            .putInt("minute", (a["minute"] as Number).toInt())
                            .putInt("keep", (a["keep"] as Number).toInt())
                            .apply()
                        BackupScheduler.schedule(this)
                        result.success(null)
                    }
                    "pickFolder" -> {
                        folderResult = result
                        folderPicker.launch(null)
                    }
                    "runNow" -> {
                        Thread {
                            val status = BackupRunner.run(this)
                            runOnUiThread { result.success(status) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
