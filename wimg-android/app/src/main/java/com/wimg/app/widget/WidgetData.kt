package com.wimg.app.widget

import android.content.Context
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

data class RecentTx(val description: String, val amount: Double)

data class WidgetData(
    val available: Double = 0.0,
    val income: Double = 0.0,
    val expenses: Double = 0.0,
    val savingsRate: Int = 0,
    val nextMerchant: String? = null,
    val nextAmount: Double? = null,
    val nextDate: String? = null,
    val recent: List<RecentTx> = emptyList(),
    val hasData: Boolean = false,
) {
    companion object {
        fun load(context: Context): WidgetData {
            val prefs = context.getSharedPreferences("wimg_widget", Context.MODE_PRIVATE)
            val jsonStr = prefs.getString("wimg_widget_data", null) ?: return WidgetData()
            return try {
                val obj = Json.parseToJsonElement(jsonStr).jsonObject
                WidgetData(
                    available = obj["available"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                    income = obj["income"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                    expenses = obj["expenses"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                    savingsRate = obj["savings_rate"]?.jsonPrimitive?.intOrNull ?: 0,
                    nextMerchant = obj["next_recurring_merchant"]?.jsonPrimitive?.contentOrNull,
                    nextAmount = obj["next_recurring_amount"]?.jsonPrimitive?.doubleOrNull,
                    nextDate = obj["next_recurring_date"]?.jsonPrimitive?.contentOrNull,
                    recent = obj["recent"]?.jsonArray?.mapNotNull { el ->
                        val o = el.jsonObject
                        val d = o["desc"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                        val a = o["amount"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
                        RecentTx(d, a)
                    } ?: emptyList(),
                    hasData = true,
                )
            } catch (_: Exception) {
                WidgetData()
            }
        }
    }
}
