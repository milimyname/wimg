package com.wimg.app.models

import kotlinx.serialization.Serializable

@Serializable
data class MonthlySummary(
    val year: Int,
    val month: Int,
    val income: Double,
    val expenses: Double,
    val available: Double,
    val tx_count: Int,
    val by_category: List<CategoryBreakdown> = emptyList(),
)

@Serializable
data class CategoryBreakdown(
    val id: Int,
    val name: String,
    val amount: Double,
    val count: Int,
)
