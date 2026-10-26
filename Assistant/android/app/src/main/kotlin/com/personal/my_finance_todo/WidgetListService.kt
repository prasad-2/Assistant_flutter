package com.personal.my_finance_todo

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Supplies the rows of the two scrolling lists inside the widget
 * (kind = "txn" or "todo"). Android calls onDataSetChanged() whenever the
 * widget is told that its data changed (see MyAppWidgetProvider.refreshAll).
 */
class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext, intent)

    /** One displayable row (already formatted). amountKind: 0 none, 1 credit, 2 debit. */
    private data class Item(
        val title: String,
        val sub: String,
        val amount: String? = null,
        val amountKind: Int = 0,
        val subWarn: Boolean = false
    )

    private class Factory(private val ctx: Context, intent: Intent) : RemoteViewsFactory {
        private val widgetId = intent.getIntExtra("widget_id", 0)
        private val kind = intent.getStringExtra("kind") ?: "txn"
        private var items: List<Item> = emptyList()

        override fun onCreate() {}
        override fun onDestroy() {}

        /** Reloads rows from the database (runs on a binder thread: DB access is fine). */
        override fun onDataSetChanged() {
            val cfg = WidgetPrefs.load(ctx, widgetId)
            if (WidgetData.hiddenByLock(ctx, cfg)) {
                items = listOf(Item("Locked", "App lock is on – open Assistant to view"))
                return
            }
            val hideAmounts = !cfg.showAmounts || WidgetData.flutterBool(ctx, "hide_balances", false)
            items = if (kind == "txn") {
                WidgetData.transactions(ctx, 15).map {
                    Item(
                        it.title, it.sub,
                        if (hideAmounts) "*****.**" else WidgetData.inr(it.paise),
                        if (it.paise >= 0) 1 else 2
                    )
                }.ifEmpty { listOf(Item("No transactions yet", "")) }
            } else {
                WidgetData.todos(ctx, 20).map { Item(it.title, it.sub, null, 0, it.overdue) }
                    .ifEmpty { listOf(Item("Nothing pending", "")) }
            }
        }

        override fun getCount() = items.size

        override fun getViewAt(position: Int): RemoteViews {
            val cfg = WidgetPrefs.load(ctx, widgetId)
            val dark = MyAppWidgetProvider.isDark(ctx, cfg.theme)
            val text = if (dark) Color.WHITE else Color.parseColor("#12312E")
            val muted = if (dark) Color.parseColor("#9FB4B1") else Color.parseColor("#5B7370")
            val green = if (dark) Color.parseColor("#66BB6A") else Color.parseColor("#2E7D32")
            val red = if (dark) Color.parseColor("#EF5350") else Color.parseColor("#C62828")

            val item = items.getOrNull(position) ?: Item("", "")
            val v = RemoteViews(ctx.packageName, R.layout.widget_row)
            v.setTextViewText(R.id.row_title, item.title)
            v.setTextColor(R.id.row_title, text)
            v.setTextViewText(R.id.row_sub, item.sub)
            v.setTextColor(R.id.row_sub, if (item.subWarn) red else muted)
            if (item.amount != null) {
                v.setViewVisibility(R.id.row_amount, android.view.View.VISIBLE)
                v.setTextViewText(R.id.row_amount, item.amount)
                v.setTextColor(R.id.row_amount, if (item.amountKind == 1) green else red)
            } else {
                v.setViewVisibility(R.id.row_amount, android.view.View.GONE)
            }
            // tapping a row opens the app (the PendingIntent template is set by the provider)
            v.setOnClickFillInIntent(R.id.row_root, Intent())
            return v
        }

        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = position.toLong()
        override fun hasStableIds() = false
    }
}
