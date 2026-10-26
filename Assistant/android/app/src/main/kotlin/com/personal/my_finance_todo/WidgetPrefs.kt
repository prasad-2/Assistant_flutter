package com.personal.my_finance_todo

import android.content.Context

/** Per-widget configuration stored in SharedPreferences. */
object WidgetPrefs {
    /**
     * theme: 0 = follow app, 1 = light, 2 = dark, 3 = follow phone system.
     * expandTxn / expandTodo: which collapsible sections are open.
     * showAmounts: print transaction values on the widget.
     * showWhenLocked: show data even while the app lock is enabled.
     */
    data class Config(
        val theme: Int,
        val accent: Int,
        val opacity: Int,
        val expandTxn: Boolean = true,
        val expandTodo: Boolean = false,
        val showAmounts: Boolean = true,
        val showWhenLocked: Boolean = false,
        val showTxnSection: Boolean = true,   // show/hide the whole transactions section
        val showTodoSection: Boolean = true   // show/hide the whole todos section
    )

    private fun prefs(c: Context) =
        c.getSharedPreferences("assistant_widget", Context.MODE_PRIVATE)

    fun load(c: Context, id: Int): Config {
        val p = prefs(c)
        return Config(
            p.getInt("theme_$id", 0),
            p.getInt("accent_$id", 0),
            p.getInt("opacity_$id", 100),
            p.getBoolean("txn_$id", true),
            p.getBoolean("todo_$id", false),
            p.getBoolean("amounts_$id", true),
            p.getBoolean("locked_$id", false),
            p.getBoolean("sectxn_$id", true),
            p.getBoolean("sectodo_$id", true)
        )
    }

    fun save(c: Context, id: Int, cfg: Config) {
        prefs(c).edit()
            .putInt("theme_$id", cfg.theme)
            .putInt("accent_$id", cfg.accent)
            .putInt("opacity_$id", cfg.opacity)
            .putBoolean("txn_$id", cfg.expandTxn)
            .putBoolean("todo_$id", cfg.expandTodo)
            .putBoolean("amounts_$id", cfg.showAmounts)
            .putBoolean("locked_$id", cfg.showWhenLocked)
            .putBoolean("sectxn_$id", cfg.showTxnSection)
            .putBoolean("sectodo_$id", cfg.showTodoSection)
            .apply()
    }

    fun remove(c: Context, id: Int) {
        val e = prefs(c).edit()
        listOf("theme", "accent", "opacity", "txn", "todo", "amounts", "locked", "sectxn", "sectodo")
            .forEach { e.remove("${it}_$id") }
        e.apply()
    }
}
