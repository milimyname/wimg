package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.CategoryBreakdown
import com.wimg.app.models.MonthlySummary
import com.wimg.app.models.Snapshot
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.MonthPicker
import com.wimg.app.ui.components.SpendingHeatmap
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import java.util.Calendar
import kotlin.math.abs

@Composable
fun AnalysisScreen(selectedAccount: String?) {
    val calendar = Calendar.getInstance()
    var year by remember { mutableIntStateOf(calendar.get(Calendar.YEAR)) }
    var month by remember { mutableIntStateOf(calendar.get(Calendar.MONTH) + 1) }
    var summary by remember { mutableStateOf<MonthlySummary?>(null) }
    var snapshots by remember { mutableStateOf<List<Snapshot>>(emptyList()) }

    LaunchedEffect(year, month, selectedAccount) {
        summary = LibWimg.getSummaryFiltered(year, month, selectedAccount)
        snapshots = LibWimg.getSnapshots()
    }

    val categories = summary?.by_category?.sortedByDescending { abs(it.amount) } ?: emptyList()
    val totalExpenses = abs(summary?.expenses ?: 0.0)

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

        // Expenses total
        item {
            Card(
                shape = WimgShapes.large,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            ) {
                Column(
                    modifier = Modifier.padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        "Ausgaben",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        formatAmountShort(summary?.expenses ?: 0.0),
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "${summary?.tx_count ?: 0} Transaktionen",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // Spending heatmap
        if (snapshots.size >= 2) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = WimgShapes.medium,
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    SpendingHeatmap(
                        snapshots = snapshots,
                        modifier = Modifier.padding(16.dp),
                    )
                }
            }
        }

        // Category breakdown
        if (categories.isNotEmpty()) {
            item {
                Text(
                    "Kategorien",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            items(categories) { cat ->
                CategoryBreakdownRow(cat, totalExpenses)
            }
        }

        // Net worth from snapshots
        if (snapshots.size >= 2) {
            item {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Vermögen",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                Card(
                    shape = WimgShapes.medium,
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    Column(modifier = Modifier.padding(20.dp)) {
                        val latest = snapshots.last()
                        val first = snapshots.first()
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Column {
                                Text(
                                    "Aktuell",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(
                                    formatAmountShort(latest.net_worth),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    "Seit Beginn",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                val growth = latest.net_worth - first.net_worth
                                Text(
                                    "${if (growth >= 0) "+" else ""}${formatAmountShort(growth)}",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = if (growth >= 0) WimgCategory.INCOME.color else MaterialTheme.colorScheme.error,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CategoryBreakdownRow(cat: CategoryBreakdown, total: Double) {
    val category = WimgCategory.fromId(cat.id)
    val pct = if (total > 0) abs(cat.amount) / total else 0.0

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .wimgCard(WimgShapes.small)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(category.color.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                category.icon,
                contentDescription = null,
                tint = category.color,
                modifier = Modifier.size(18.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                category.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { pct.toFloat() },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = category.color,
                trackColor = category.color.copy(alpha = 0.1f),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(horizontalAlignment = Alignment.End) {
            Text(
                formatAmountShort(cat.amount),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "${(pct * 100).toInt()}%",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
