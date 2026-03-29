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
import com.wimg.app.models.RecurringPattern
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import com.wimg.app.ui.theme.wimgHero
import kotlin.math.abs

private val INTERVAL_LABELS = mapOf(
    "weekly" to "Wöchentlich",
    "monthly" to "Monatlich",
    "quarterly" to "Vierteljährlich",
    "annual" to "Jährlich",
)

@Composable
fun RecurringScreen() {
    var patterns by remember { mutableStateOf<List<RecurringPattern>>(emptyList()) }
    var detecting by remember { mutableStateOf(false) }

    fun reload() { patterns = LibWimg.getRecurring() }

    LaunchedEffect(Unit) { reload() }

    val active = patterns.filter { it.active == 1 }
    val grouped = active.groupBy { it.interval }.toSortedMap()
    val monthlyTotal = active.filter { it.interval == "monthly" }.sumOf { abs(it.amount) }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (patterns.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("🔄", fontSize = 48.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Keine Muster erkannt", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text("Importiere Transaktionen und tippe Erkennen", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(16.dp))
                        Button(
                            onClick = {
                                detecting = true
                                LibWimg.detectRecurring()
                                reload()
                                detecting = false
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
                        ) {
                            Text(if (detecting) "Erkennung..." else "Erkennen", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        } else {
            // Hero
            item {
                Box(modifier = Modifier.fillMaxWidth().wimgHero()) {
                    Column(modifier = Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Monatliche Fixkosten", style = MaterialTheme.typography.labelMedium, color = WimgColors.heroText.copy(alpha = 0.7f))
                        Spacer(Modifier.height(4.dp))
                        Text(formatAmountShort(monthlyTotal), fontSize = 32.sp, fontWeight = FontWeight.Black, color = WimgColors.heroText)
                        Text("${active.size} aktive Muster", style = MaterialTheme.typography.bodySmall, color = WimgColors.heroText.copy(alpha = 0.7f))
                    }
                }
            }

            // Detect button
            item {
                OutlinedButton(
                    onClick = {
                        detecting = true
                        LibWimg.detectRecurring()
                        reload()
                        detecting = false
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = WimgShapes.small,
                ) {
                    Text(if (detecting) "Erkennung..." else "Erneut erkennen", fontWeight = FontWeight.Bold)
                }
            }

            // Grouped by interval
            grouped.forEach { (interval, items) ->
                item {
                    Text(
                        INTERVAL_LABELS[interval] ?: interval,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
                items(items, key = { it.id }) { pattern ->
                    PatternRow(pattern)
                }
            }
        }
    }
}

@Composable
private fun PatternRow(pattern: RecurringPattern) {
    val category = WimgCategory.fromId(pattern.category)

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
            Icon(category.icon, contentDescription = null, tint = category.color, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(pattern.merchant, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (pattern.next_due != null) {
                    Text(pattern.next_due, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(formatAmountShort(abs(pattern.amount)), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
            if (pattern.price_change != null && pattern.price_change != 0.0) {
                Text(
                    "${if (pattern.price_change > 0) "+" else ""}${formatAmountShort(pattern.price_change)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (pattern.price_change > 0) MaterialTheme.colorScheme.error else WimgCategory.INCOME.color,
                )
            }
        }
    }
}
