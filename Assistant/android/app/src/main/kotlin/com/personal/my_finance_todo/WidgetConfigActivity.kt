package com.personal.my_finance_todo

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

/**
 * Shown when the widget is added (and when it is reconfigured). Lets the user
 * pick the theme (app / light / dark / system), the accent colour and the
 * background transparency. The UI is built in code to keep the project small.
 */
class WidgetConfigActivity : Activity() {

    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var themeChoice = 0
    private var accentChoice = 0
    private var opacityChoice = 100
    private var cfgOld = WidgetPrefs.Config(0, 0, 100)
    private var showAmounts = true
    private var showWhenLocked = false
    private var showTxnSection = true
    private var showTodoSection = true
    private val accentViews = mutableListOf<View>()

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // If the user backs out, the widget must not be added.
        setResult(RESULT_CANCELED)

        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val cfg = WidgetPrefs.load(this, widgetId)
        cfgOld = cfg
        showAmounts = cfg.showAmounts
        showWhenLocked = cfg.showWhenLocked
        showTxnSection = cfg.showTxnSection
        showTodoSection = cfg.showTodoSection
        themeChoice = cfg.theme
        accentChoice = cfg.accent
        opacityChoice = cfg.opacity

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
        }

        root.addView(heading("Widget theme"))
        val group = RadioGroup(this)
        val labels = listOf("Follow app theme", "Light", "Dark", "Follow phone system")
        labels.forEachIndexed { i, text ->
            group.addView(RadioButton(this).apply {
                id = 1000 + i
                this.text = text
                isChecked = (i == themeChoice)
            })
        }
        group.setOnCheckedChangeListener { _, checked -> themeChoice = checked - 1000 }
        root.addView(group)

        root.addView(heading("Accent colour"))
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        MyAppWidgetProvider.ACCENTS.forEachIndexed { i, color ->
            val dot = View(this)
            dot.layoutParams = LinearLayout.LayoutParams(dp(38), dp(38)).apply {
                setMargins(0, dp(6), dp(10), dp(6))
            }
            dot.tag = color
            dot.setOnClickListener { accentChoice = i; refreshAccents() }
            accentViews.add(dot)
            row.addView(dot)
        }
        root.addView(row)
        refreshAccents()

        val opacityLabel = heading("Background opacity: $opacityChoice%")
        root.addView(opacityLabel)
        root.addView(SeekBar(this).apply {
            max = 80                       // 20..100 %
            progress = opacityChoice - 20
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) {
                    opacityChoice = p + 20
                    opacityLabel.text = "Background opacity: $opacityChoice%"
                }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
        })

        root.addView(heading("Sections"))
        root.addView(CheckBox(this).apply {
            text = "Show transactions"
            isChecked = showTxnSection
            setOnCheckedChangeListener { _, c -> showTxnSection = c }
        })
        root.addView(CheckBox(this).apply {
            text = "Show todos"
            isChecked = showTodoSection
            setOnCheckedChangeListener { _, c -> showTodoSection = c }
        })

        root.addView(heading("Privacy"))
        root.addView(CheckBox(this).apply {
            text = "Show transaction amounts"
            isChecked = showAmounts
            setOnCheckedChangeListener { _, c -> showAmounts = c }
        })
        root.addView(CheckBox(this).apply {
            text = "Show data even when app lock is on"
            isChecked = showWhenLocked
            setOnCheckedChangeListener { _, c -> showWhenLocked = c }
        })

        root.addView(Button(this).apply {
            text = "Save"
            setOnClickListener { save() }
        })

        setContentView(ScrollView(this).apply { addView(root) })
    }

    private fun heading(t: String) = TextView(this).apply {
        text = t
        textSize = 15f
        setPadding(0, dp(16), 0, dp(4))
        setTypeface(typeface, android.graphics.Typeface.BOLD)
    }

    /** Draws the accent dots; the selected one gets a dark ring. */
    private fun refreshAccents() {
        accentViews.forEachIndexed { i, v ->
            v.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(v.tag as Int)
                if (i == accentChoice) setStroke(dp(3), Color.BLACK)
            }
        }
    }

    /** Stores the settings, redraws the widget and finishes with RESULT_OK. */
    private fun save() {
        WidgetPrefs.save(this, widgetId,
            cfgOld.copy(theme = themeChoice, accent = accentChoice, opacity = opacityChoice,
                showAmounts = showAmounts, showWhenLocked = showWhenLocked,
                showTxnSection = showTxnSection, showTodoSection = showTodoSection))
        MyAppWidgetProvider.update(this, AppWidgetManager.getInstance(this), widgetId)
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }
}
