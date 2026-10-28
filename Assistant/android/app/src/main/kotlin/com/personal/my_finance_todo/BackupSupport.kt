package com.personal.my_finance_todo

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.provider.DocumentsContract
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Scheduled (automatic) backup of the app database, done natively so it works
 * even when the app is closed. The user picks a folder with the system folder
 * picker (Storage Access Framework), so no storage permission is needed.
 *
 * Settings live in their own SharedPreferences file ("assistant_backup").
 */
object BackupPrefs {
    fun get(c: Context): SharedPreferences =
        c.getSharedPreferences("assistant_backup", Context.MODE_PRIVATE)
}

object BackupScheduler {
    const val ACTION = "com.personal.my_finance_todo.AUTO_BACKUP"
    private const val REQUEST = 7001

    /**
     * Next run time: [intervalDays] after the last successful backup (at the
     * chosen time of day). When that moment is already past, the next
     * occurrence of the chosen time of day is used (a missed backup runs once).
     */
    fun nextTrigger(p: SharedPreferences, now: Long): Long {
        val hour = p.getInt("hour", 2)
        val minute = p.getInt("minute", 0)
        val interval = p.getInt("interval_days", 1).coerceAtLeast(1)
        val last = p.getLong("last_time", 0L)
        val cal = Calendar.getInstance()
        if (last > 0) {
            cal.timeInMillis = last
            cal.add(Calendar.DAY_OF_YEAR, interval)
        } else {
            cal.timeInMillis = now
        }
        cal.set(Calendar.HOUR_OF_DAY, hour)
        cal.set(Calendar.MINUTE, minute)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        while (cal.timeInMillis <= now) cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }

    /** (Re)arms the alarm according to the saved settings; cancels it when disabled. */
    fun schedule(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            ctx, REQUEST,
            Intent(ctx, BackupReceiver::class.java).setAction(ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.cancel(pi)
        val p = BackupPrefs.get(ctx)
        if (!p.getBoolean("enabled", false)) return
        am.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, nextTrigger(p, System.currentTimeMillis()), pi)
    }
}

object BackupRunner {
    private const val PREFIX = "assistant_backup_"

    /** Human readable name of a picked folder, e.g. "Internal storage/Backups". */
    fun displayName(tree: Uri): String =
        Uri.decode(tree.lastPathSegment ?: "").replace("primary:", "Internal storage/")

    private fun fail(p: SharedPreferences, msg: String): String {
        p.edit().putString("last_status", "Failed: $msg").apply()
        return "Failed: $msg"
    }

    /** Copies the database into the chosen folder. Returns "OK: <file>" or "Failed: <why>". */
    fun run(ctx: Context): String {
        val p = BackupPrefs.get(ctx)
        val uriStr = p.getString("tree_uri", null) ?: return fail(p, "no backup folder selected")
        val db = ctx.getDatabasePath("finance_todo.db")
        if (!db.exists()) return fail(p, "database not found")
        return try {
            val tree = Uri.parse(uriStr)
            val resolver = ctx.contentResolver
            val parent = DocumentsContract.buildDocumentUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree))
            val name = PREFIX +
                SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".db"
            val doc = DocumentsContract.createDocument(
                resolver, parent, "application/octet-stream", name)
                ?: return fail(p, "could not create the file in the folder")
            resolver.openOutputStream(doc)?.use { out ->
                db.inputStream().use { it.copyTo(out) }
            } ?: return fail(p, "could not write to the folder")
            prune(ctx, tree, p.getInt("keep", 10))
            p.edit()
                .putLong("last_time", System.currentTimeMillis())
                .putString("last_status", "OK: $name")
                .apply()
            "OK: $name"
        } catch (e: Exception) {
            fail(p, e.message ?: "unknown error")
        }
    }

    /** Keeps only the newest [keep] automatic backups (older ones are deleted). */
    private fun prune(ctx: Context, tree: Uri, keep: Int) {
        if (keep <= 0) return
        val resolver = ctx.contentResolver
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree))
        val files = ArrayList<Pair<String, String>>() // name to document id
        resolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(1) ?: continue
                if (name.startsWith(PREFIX) && name.endsWith(".db")) {
                    files.add(name to c.getString(0))
                }
            }
        }
        // names contain the timestamp, so alphabetical order == time order
        files.sortByDescending { it.first }
        files.drop(keep).forEach {
            try {
                DocumentsContract.deleteDocument(
                    resolver, DocumentsContract.buildDocumentUriUsingTree(tree, it.second))
            } catch (_: Exception) {
            }
        }
    }
}

/** Runs the backup when the alarm fires and re-arms the next one; also re-arms after reboot. */
class BackupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == BackupScheduler.ACTION) {
            val pending = goAsync()
            Thread {
                try {
                    BackupRunner.run(context)
                } finally {
                    BackupScheduler.schedule(context)
                    pending.finish()
                }
            }.start()
        } else {
            // BOOT_COMPLETED / MY_PACKAGE_REPLACED
            BackupScheduler.schedule(context)
        }
    }
}
