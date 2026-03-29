package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.MonthlySummary
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.MonthPicker
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import com.wimg.app.ui.theme.wimgHero
import java.text.DateFormatSymbols
import java.util.Calendar
import kotlin.math.abs

@Composable
fun ReviewScreen(selectedAccount: String?) {
    val calendar = Calendar.getInstance()
    var year by remember { mutableIntStateOf(calendar.get(Calendar.YEAR)) }
    var month by remember { mutableIntStateOf(calendar.get(Calendar.MONTH) + 1) }
    var summary by remember { mutableStateOf<MonthlySummary?>(null) }

    LaunchedEffect(year, month, selectedAccount) {
        summary = LibWimg.getSummaryFiltered(year, month, selectedAccount)
    }

    val income = summary?.income ?: 0.0
    val expenses = summary?.expenses ?: 0.0
    val saved = income + expenses // expenses is negative
    val monthNames = DateFormatSymbols().months

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Month picker
        item {
            MonthPicker(year = year, month = month, onChanged = { y, m -> year = y; month = m })
        }

        // Savings hero
        item {
            Box(modifier = Modifier.fillMaxWidth().wimgHero()) {
                Column(modifier = Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (saved >= 0) "Gespart" else "Defizit",
                        style = MaterialTheme.typography.labelMedium,
                        color = WimgColors.heroText.copy(alpha = 0.7f),
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        formatAmountShort(abs(saved)),
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Black,
                        color = WimgColors.heroText,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        when {
                            saved > 0 -> "Dein Sparziel wurde erreicht. Super!"
                            saved == 0.0 -> "Einnahmen und Ausgaben waren ausgeglichen."
                            else -> "Diesen Monat hast du mehr ausgegeben als eingenommen."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = WimgColors.heroText.copy(alpha = 0.7f),
                    )
                }
            }
        }

        // Income / Expenses
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatCard("Einnahmen", income, Icons.Outlined.ArrowDownward, WimgCategory.INCOME.color, Modifier.weight(1f))
                StatCard("Ausgaben", expenses, Icons.Outlined.ArrowUpward, MaterialTheme.colorScheme.error, Modifier.weight(1f))
            }
        }

        // Top categories
        val categories = summary?.by_category?.sortedByDescending { abs(it.amount) }?.take(5) ?: emptyList()
        if (categories.isNotEmpty()) {
            item {
                Text("Top Kategorien", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
            }
            items(categories) { cat ->
                val category = WimgCategory.fromId(cat.id)
                Row(
                    modifier = Modifier.fillMaxWidth().wimgCard(WimgShapes.small).padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(category.icon, contentDescription = null, tint = category.color, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(category.label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                    Text(formatAmountShort(cat.amount), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                }
            }
        }

        // Stats
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatCard("Transaktionen", (summary?.tx_count ?: 0).toDouble(), modifier = Modifier.weight(1f), isCount = true)
                val savingsRate = if (income > 0) (saved / income * 100) else 0.0
                StatCard("Sparquote", savingsRate, modifier = Modifier.weight(1f), suffix = "%")
            }
        }
    }
}

@Composable
private fun StatCard(
    title: String,
    value: Double,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    iconColor: androidx.compose.ui.graphics.Color? = null,
    modifier: Modifier = Modifier,
    isCount: Boolean = false,
    suffix: String = "",
) {
    Column(modifier = modifier.wimgCard(WimgShapes.small).padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) {
                    Icon(icon, contentDescription = null, tint = iconColor ?: MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                }
                Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                if (isCount) "${value.toInt()}" else if (suffix.isNotEmpty()) "${value.toInt()}$suffix" else formatAmountShort(value),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
    }
}
