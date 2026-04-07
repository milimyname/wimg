package com.wimg.app.services

import android.content.Context
import androidx.glance.appwidget.updateAll
import com.wimg.app.bridge.LibWimg
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.Calendar
import kotlin.math.abs

object WidgetDataWriter {
    private const val PREFS = "wimg_widget"
    private const val KEY = "wimg_widget_data"

    fun writeSummary(context: Context) {
        val cal = Calendar.getInstance()
        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1

        val summary = LibWimg.getSummaryFiltered(year, month, null) ?: return
        val income = summary.income
        val expenses = summary.expenses
        val savingsRate = if (income > 0) ((income - expenses) / income * 100).toInt() else 0

        val recurring = LibWimg.getRecurring()
            .filter { it.active != 0 && it.next_due != null }
            .sortedBy { it.next_due }

        val recent = LibWimg.getTransactions()
            .filter { !it.isExcluded }
            .sortedByDescending { it.date }
            .take(5)

        val data = buildJsonObject {
            put("available", summary.available)
            put("income", income)
            put("expenses", expenses)
            put("savings_rate", savingsRate)
            put("updated_at", System.currentTimeMillis() / 1000)
            recurring.firstOrNull()?.let { next ->
                put("next_recurring_merchant", next.merchant)
                put("next_recurring_amount", next.amount)
                put("next_recurring_date", next.next_due)
            }
            put("recent", buildJsonArray {
                recent.forEach { tx ->
                    add(buildJsonObject {
                        put("desc", tx.description)
                        put("amount", tx.amount)
                    })
                }
            })
        }

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, data.toString()).apply()

        // Trigger widget refresh
        CoroutineScope(Dispatchers.IO).launch {
            try {
                com.wimg.app.widget.WimgSmallWidget().updateAll(context)
                com.wimg.app.widget.WimgMediumWidget().updateAll(context)
                com.wimg.app.widget.WimgLargeWidget().updateAll(context)
            } catch (_: Exception) { }
        }
    }
}
