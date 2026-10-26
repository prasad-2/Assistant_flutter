package com.personal.my_finance_todo

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Read-only access to the app's SQLite database (same file the Flutter side
 * uses) so the widget can list recent transactions and pending todos.
 */
object WidgetData {
    /** A transaction row: amount is SIGNED paise (credit > 0). */
    data class Txn(val title: String, val sub: String, val paise: Long)

    /** A todo row. */
    data class TodoRow(val title: String, val sub: String, val overdue: Boolean)

    private val dateFmt = SimpleDateFormat("dd-MMM-yy HH:mm", Locale.getDefault())

    /** sqflite's databases folder == Context.getDatabasePath's parent. */
    private fun open(ctx: Context): SQLiteDatabase? {
        val f = ctx.getDatabasePath("finance_todo.db")
        if (!f.exists()) return null
        return try {
            SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READONLY)
        } catch (e: Exception) {
            null
        }
    }

    /** Values Flutter's shared_preferences wrote (keys are prefixed "flutter."). */
    fun flutterBool(ctx: Context, key: String, def: Boolean): Boolean {
        val p = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return (p.all["flutter.$key"] as? Boolean) ?: def
    }

    /** True when the widget must NOT show data because the app lock is on. */
    fun hiddenByLock(ctx: Context, cfg: WidgetPrefs.Config): Boolean =
        flutterBool(ctx, "lock_enabled", false) && !cfg.showWhenLocked

    /** Latest transactions (actual + scheduled), newest first. */
    fun transactions(ctx: Context, limit: Int): List<Txn> {
        val db = open(ctx) ?: return emptyList()
        val out = ArrayList<Txn>()
        try {
            db.rawQuery(
                "SELECT t.description, t.amount, t.status, t.date_time, c.name " +
                    "FROM transactions t JOIN categories c ON c.id = t.category_id " +
                    "ORDER BY t.date_time DESC, t.id DESC LIMIT $limit", null
            ).use { c ->
                while (c.moveToNext()) {
                    val scheduled = c.getString(2) == "scheduled"
                    val sub = dateFmt.format(Date(c.getLong(3))) + "  •  " + c.getString(4) +
                        if (scheduled) "  •  Scheduled" else ""
                    out.add(Txn(c.getString(0), sub, c.getLong(1)))
                }
            }
        } catch (e: Exception) {
            // table missing / db busy: show nothing
        } finally {
            db.close()
        }
        return out
    }

    /** Pending todos ordered by due date (undated last). */
    fun todos(ctx: Context, limit: Int): List<TodoRow> {
        val db = open(ctx) ?: return emptyList()
        val out = ArrayList<TodoRow>()
        val now = System.currentTimeMillis()
        try {
            db.rawQuery(
                "SELECT title, due_at FROM todos WHERE is_done = 0 " +
                    "ORDER BY CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at, id LIMIT $limit",
                null
            ).use { c ->
                while (c.moveToNext()) {
                    val due = if (c.isNull(1)) null else c.getLong(1)
                    out.add(
                        TodoRow(
                            c.getString(0),
                            if (due == null) "No due date" else dateFmt.format(Date(due)),
                            due != null && due < now
                        )
                    )
                }
            }
        } catch (e: Exception) {
        } finally {
            db.close()
        }
        return out
    }

    fun todoCount(ctx: Context): Int {
        val db = open(ctx) ?: return 0
        return try {
            db.rawQuery("SELECT COUNT(*) FROM todos WHERE is_done = 0", null)
                .use { if (it.moveToFirst()) it.getInt(0) else 0 }
        } catch (e: Exception) {
            0
        } finally {
            db.close()
        }
    }

    /** Paise -> "1,00,000.00" (Indian grouping, no currency symbol, no +/- prefix). */
    fun inr(paise: Long): String {
        val f = NumberFormat.getNumberInstance(Locale("en", "IN"))
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.format(Math.abs(paise) / 100.0)
    }
}
