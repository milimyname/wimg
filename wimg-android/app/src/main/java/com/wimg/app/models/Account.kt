package com.wimg.app.models

import kotlinx.serialization.Serializable

@Serializable
data class Account(
    val id: String,
    val name: String,
    val bank: String = "",
    val color: String = "#007AFF",
)

@Serializable
data class RecurringPattern(
    val id: String,
    val merchant: String,
    val amount: Double,
    val interval: String,
    val category: Int,
    val last_seen: String,
    val next_due: String? = null,
    val active: Int = 1,
    val prev_amount: Double? = null,
    val price_change: Double? = null,
)

@Serializable
data class Snapshot(
    val id: String,
    val date: String,
    val net_worth: Double,
    val income: Double,
    val expenses: Double,
    val tx_count: Int,
)
