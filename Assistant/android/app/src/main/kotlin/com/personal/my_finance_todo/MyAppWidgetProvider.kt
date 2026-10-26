package com.personal.my_finance_todo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews

/**
 * Home-screen widget:
 *   * header (tap = open the app)
 *   * two buttons: add transaction / add todo (open the transparent QuickAddActivity)
 *   * two COLLAPSIBLE sections: recent transactions and pending todos
 *
 * Theme / accent / transparency / privacy options come from WidgetConfigActivity.
 */
class MyAppWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        ids.forEach { WidgetPrefs.remove(context, it) }
    }

    /** Handles the expand / collapse taps of the two section headers. */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val id = intent.getIntExtra("widget_id", AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                val cfg = WidgetPrefs.load(context, id)
                val updated = if (intent.getStringExtra("section") == "txn")
                    cfg.copy(expandTxn = !cfg.expandTxn)
                else
                    cfg.copy(expandTodo = !cfg.expandTodo)
                WidgetPrefs.save(context, id, updated)
                update(context, AppWidgetManager.getInstance(context), id)
            }
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        const val ACTION_TOGGLE = "com.personal.my_finance_todo.WIDGET_TOGGLE"

        /** Accent colours offered in the widget settings. */
        val ACCENTS: IntArray = intArrayOf(
            Color.parseColor("#00897B"), // teal
            Color.parseColor("#1E88E5"), // blue
            Color.parseColor("#8E24AA"), // purple
            Color.parseColor("#F4511E"), // orange
            Color.parseColor("#D81B60"), // pink
            Color.parseColor("#43A047")  // green
        )

        /** Redraws every placed widget and reloads the lists (data changed). */
        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, MyAppWidgetProvider::class.java))
            ids.forEach { update(context, mgr, it) }
        }

        private fun systemDark(context: Context): Boolean =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES

        /**
         * Light or dark for the chosen widget theme. "Follow app theme" reads
         * the value Flutter stored (0 = system, 1 = light, 2 = dark).
         */
        fun isDark(context: Context, theme: Int): Boolean = when (theme) {
            1 -> false
            2 -> true
            3 -> systemDark(context)
            else -> {
                val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                when ((p.all["flutter.theme"] as? Number)?.toInt() ?: 0) {
                    1 -> false
                    2 -> true
                    else -> systemDark(context)
                }
            }
        }

        private fun immutable() = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        /** Opens the quick-add dialog in the given mode ("transaction" / "todo"). */
        private fun quickAdd(context: Context, widgetId: Int, mode: String, req: Int): PendingIntent {
            val intent = Intent(context, QuickAddActivity::class.java).apply {
                putExtra("mode", mode)
                putExtra("background_mode", "transparent") // see-through Flutter surface
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                data = Uri.parse("assistant://quickadd/$mode/$widgetId")
            }
            return PendingIntent.getActivity(context, widgetId * 10 + req, intent, immutable())
        }

        /** Opens the full app. */
        private fun openApp(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            }
            return PendingIntent.getActivity(context, widgetId * 10 + 3, intent, immutable())
        }

        /** Template for list-row taps (rows only add an empty "fill-in" intent). */
        private fun rowTemplate(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            }
            // templates that receive fill-in intents must be mutable on Android 12+
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            return PendingIntent.getActivity(context, widgetId * 10 + 4, intent, flags)
        }

        /** Broadcast fired by tapping a section header. */
        private fun toggle(context: Context, widgetId: Int, section: String, req: Int): PendingIntent {
            val intent = Intent(context, MyAppWidgetProvider::class.java).apply {
                action = ACTION_TOGGLE
                putExtra("widget_id", widgetId)
                putExtra("section", section)
                data = Uri.parse("assistant://toggle/$section/$widgetId")
            }
            return PendingIntent.getBroadcast(context, widgetId * 10 + req, intent, immutable())
        }

        /** Intent that binds a scrolling list to WidgetListService. */
        private fun listIntent(context: Context, widgetId: Int, kind: String): Intent =
            Intent(context, WidgetListService::class.java).apply {
                putExtra("widget_id", widgetId)
                putExtra("kind", kind)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME)) // unique per widget/list
            }

        /** Builds and pushes the RemoteViews of one widget. */
        fun update(context: Context, mgr: AppWidgetManager, id: Int) {
            val cfg = WidgetPrefs.load(context, id)
            val dark = isDark(context, cfg.theme)
            val accent = ACCENTS[cfg.accent.coerceIn(0, ACCENTS.size - 1)]

            // palette for the chosen theme
            val bg = if (dark) Color.parseColor("#1E2A29") else Color.parseColor("#F6FBFA")
            val title = if (dark) Color.WHITE else Color.parseColor("#12312E")
            val subtitle = if (dark) Color.parseColor("#9FB4B1") else Color.parseColor("#5B7370")

            val v = RemoteViews(context.packageName, R.layout.widget_main)

            // background: opaque colour filter + transparency from the setting
            v.setInt(R.id.widget_bg, "setColorFilter", bg)
            v.setInt(R.id.widget_bg, "setImageAlpha", (cfg.opacity.coerceIn(20, 100) * 255) / 100)
            v.setTextColor(R.id.widget_title, title)
            v.setTextColor(R.id.widget_subtitle, subtitle)

            // primary (filled) button: Transaction
            v.setInt(R.id.btn_txn_bg, "setColorFilter", accent)
            v.setInt(R.id.btn_txn_bg, "setImageAlpha", 255)
            v.setInt(R.id.btn_txn_icon, "setColorFilter", Color.WHITE)
            v.setTextColor(R.id.btn_txn_label, Color.WHITE)

            // tonal button: Todo (accent tint + accent text)
            v.setInt(R.id.btn_todo_bg, "setColorFilter", accent)
            v.setInt(R.id.btn_todo_bg, "setImageAlpha", if (dark) 70 else 45)
            v.setInt(R.id.btn_todo_icon, "setColorFilter", accent)
            v.setTextColor(R.id.btn_todo_label, if (dark) Color.WHITE else accent)

            v.setOnClickPendingIntent(R.id.btn_txn, quickAdd(context, id, "transaction", 1))
            v.setOnClickPendingIntent(R.id.btn_todo, quickAdd(context, id, "todo", 2))
            v.setOnClickPendingIntent(R.id.widget_header, openApp(context, id))

            // ── collapsible sections ──
            val locked = WidgetData.hiddenByLock(context, cfg)
            val pending = if (locked) 0 else WidgetData.todoCount(context)

            section(v, context, id, "txn", cfg.showTxnSection, cfg.expandTxn, accent, title, subtitle,
                R.id.txn_header, R.id.txn_chevron, R.id.txn_title, R.id.txn_meta, R.id.list_txn,
                "Recent transactions", if (locked) "locked" else "latest 15", 5)
            section(v, context, id, "todo", cfg.showTodoSection, cfg.expandTodo, accent, title, subtitle,
                R.id.todo_header, R.id.todo_chevron, R.id.todo_title, R.id.todo_meta, R.id.list_todo,
                "Todos", if (locked) "locked" else "$pending pending", 6)

            mgr.updateAppWidget(id, v)
            // tell the lists to reload their rows
            mgr.notifyAppWidgetViewDataChanged(id, R.id.list_txn)
            mgr.notifyAppWidgetViewDataChanged(id, R.id.list_todo)
        }

        /** Applies colours / visibility / click handlers of one collapsible section. */
        private fun section(
            v: RemoteViews, context: Context, id: Int, kind: String,
            visible: Boolean, expanded: Boolean,
            accent: Int, title: Int, subtitle: Int,
            headerId: Int, chevronId: Int, titleId: Int, metaId: Int, listId: Int,
            titleText: String, meta: String, req: Int
        ) {
            v.setTextViewText(titleId, titleText)
            v.setTextColor(titleId, title)
            v.setTextViewText(metaId, meta)
            v.setTextColor(metaId, subtitle)
            v.setImageViewResource(chevronId,
                if (expanded) R.drawable.ic_chevron_up else R.drawable.ic_chevron_down)
            v.setInt(chevronId, "setColorFilter", accent)
            // the user can hide a whole section in the widget settings
            v.setViewVisibility(headerId, if (visible) View.VISIBLE else View.GONE)
            v.setViewVisibility(listId,
                if (visible && expanded) View.VISIBLE else View.GONE)
            v.setRemoteAdapter(listId, listIntent(context, id, kind))
            v.setPendingIntentTemplate(listId, rowTemplate(context, id))
            v.setOnClickPendingIntent(headerId, toggle(context, id, kind, req))
        }
    }
}
