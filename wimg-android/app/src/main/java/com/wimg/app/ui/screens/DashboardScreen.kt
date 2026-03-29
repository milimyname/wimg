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
import com.wimg.app.models.CategoryBreakdown
import com.wimg.app.models.MonthlySummary
import com.wimg.app.models.WimgCategory
import com.wimg.app.services.DemoDataService
import com.wimg.app.ui.components.MonthPicker
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import java.util.Calendar

@Composable
fun DashboardScreen(selectedAccount: String?) {
    val calendar = Calendar.getInstance()
    var year by remember { mutableIntStateOf(calendar.get(Calendar.YEAR)) }
    var month by remember { mutableIntStateOf(calendar.get(Calendar.MONTH) + 1) }
    var summary by remember { mutableStateOf<MonthlySummary?>(null) }

    LaunchedEffect(year, month, selectedAccount) {
        summary = LibWimg.getSummaryFiltered(year, month, selectedAccount)
    }

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

        // Hero card
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = WimgShapes.large,
                colors = CardDefaults.cardColors(containerColor = WimgColors.accent),
            ) {
                Column(
                    modifier = Modifier.padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        "Verfügbares Einkommen",
                        style = MaterialTheme.typography.labelMedium,
                        color = WimgColors.heroText.copy(alpha = 0.7f),
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        formatAmountShort(summary?.available ?: 0.0),
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Black,
                        color = WimgColors.heroText,
                    )
                    val income = summary?.income ?: 0.0
                    if (income > 0) {
                        val sparquote = ((income + (summary?.expenses ?: 0.0)) / income * 100).toInt()
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Sparquote: $sparquote%",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = WimgColors.heroText.copy(alpha = 0.6f),
                        )
                    }
                }
            }
        }

        // Income / Expenses row
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SummaryCard(
                    title = "Einnahmen",
                    amount = summary?.income ?: 0.0,
                    icon = Icons.Outlined.ArrowDownward,
                    iconColor = WimgCategory.INCOME.color,
                    modifier = Modifier.weight(1f),
                )
                SummaryCard(
                    title = "Ausgaben",
                    amount = summary?.expenses ?: 0.0,
                    icon = Icons.Outlined.ArrowUpward,
                    iconColor = MaterialTheme.colorScheme.error,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        // Category breakdown
        val categories = summary?.by_category ?: emptyList()
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
                CategoryRow(cat)
            }
        }

        // Empty state
        if (summary == null || (summary?.tx_count ?: 0) == 0) {
            item {
                val context = androidx.compose.ui.platform.LocalContext.current
                var loadingDemo by remember { mutableStateOf(false) }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("📋", fontSize = 48.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Keine Daten",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        "Importiere eine CSV-Datei um loszulegen",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = {
                            loadingDemo = true
                            DemoDataService.loadDemoData(context)
                            summary = LibWimg.getSummaryFiltered(year, month, selectedAccount)
                            loadingDemo = false
                        },
                        enabled = !loadingDemo,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.onBackground,
                            contentColor = MaterialTheme.colorScheme.background,
                        ),
                        shape = WimgShapes.small,
                    ) {
                        Text(
                            if (loadingDemo) "Lade..." else "Beispieldaten laden",
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(vertical = 4.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SummaryCard(
    title: String,
    amount: Double,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconColor: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier,
        shape = WimgShapes.small,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = iconColor,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    title,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                formatAmountShort(amount),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun CategoryRow(cat: CategoryBreakdown) {
    val category = WimgCategory.fromId(cat.id)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            category.icon,
            contentDescription = null,
            tint = category.color,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(12.dp))
        Text(
            category.label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        Text(
            formatAmountShort(cat.amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}
