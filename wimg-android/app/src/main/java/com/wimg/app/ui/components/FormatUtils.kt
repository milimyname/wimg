package com.wimg.app.ui.components

import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs

private val germanFormat = NumberFormat.getCurrencyInstance(Locale.GERMANY)

fun formatAmount(amount: Double): String = germanFormat.format(amount)

fun formatAmountShort(amount: Double): String {
    val abs = abs(amount)
    return if (abs >= 1000) {
        String.format(Locale.GERMANY, "%,.0f €", amount)
    } else {
        String.format(Locale.GERMANY, "%,.2f €", amount)
    }
}
