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
import java.text.DateFormatSymbols
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs

private val INTERVAL_LABELS = mapOf(
    "weekly" to "Wöchentlich",
    "monthly" to "Monatlich",
    "quarterly" to "Vierteljährlich",
    "annual" to "Jährlich",
)

private val INTERVAL_MONTHS = mapOf(
    "weekly" to 0,
    "monthly" to 1,
    "quarterly" to 3,
    "annual" to 12,
)

private data class FuturePayment(
    val date: Date,
    val merchant: String,
    val amount: Double,
    val category: Int,
    val interval: String,
    val monthKey: String,
)

@Composable
fun RecurringScreen() {
    var patterns by remember { mutableStateOf<List<RecurringPattern>>(emptyList()) }
    var detecting by remember { mutableStateOf(false) }
    var selectedTab by remember { mutableIntStateOf(0) }

    fun reload() { patterns = LibWimg.getRecurring() }

    LaunchedEffect(Unit) { reload() }

    val active = patterns.filter { it.active == 1 }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        // Segmented tab
        if (active.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(selected = selectedTab == 0, onClick = { selectedTab = 0 }, label = { Text("Abonnements") }, modifier = Modifier.weight(1f))
                FilterChip(selected = selectedTab == 1, onClick = { selectedTab = 1 }, label = { Text("Kalender") }, modifier = Modifier.weight(1f))
            }
        }

        if (selectedTab == 0) {
            SubscriptionsTab(active, patterns.isEmpty(), detecting, onDetect = {
                detecting = true
                LibWimg.detectRecurring()
                reload()
                detecting = false
            })
        } else {
            CalendarTab(active)
        }
    }
}

@Composable
private fun SubscriptionsTab(
    active: List<RecurringPattern>,
    isEmpty: Boolean,
    detecting: Boolean,
    onDetect: () -> Unit,
) {
    val grouped = active.groupBy { it.interval }.toSortedMap()
    val monthlyTotal = active.filter { it.interval == "monthly" }.sumOf { abs(it.amount) }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (isEmpty) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("🔄", fontSize = 48.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Keine Muster erkannt", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text("Importiere Transaktionen und tippe Erkennen", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = onDetect, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background)) {
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

            item {
                OutlinedButton(onClick = onDetect, modifier = Modifier.fillMaxWidth(), shape = WimgShapes.small) {
                    Text(if (detecting) "Erkennung..." else "Erneut erkennen", fontWeight = FontWeight.Bold)
                }
            }

            grouped.forEach { (interval, items) ->
                item {
                    Text(INTERVAL_LABELS[interval] ?: interval, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
                }
                items(items, key = { it.id }) { pattern ->
                    PatternRow(pattern)
                }
            }
        }
    }
}

@Composable
private fun CalendarTab(active: List<RecurringPattern>) {
    // Project future payments for 12 months
    val payments = remember(active) {
        val cal = Calendar.getInstance()
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val monthSdf = SimpleDateFormat("yyyy-MM", Locale.getDefault())
        val result = mutableListOf<FuturePayment>()

        active.forEach { pattern ->
            val nextDue = pattern.next_due?.let { try { sdf.parse(it) } catch (_: Exception) { null } } ?: return@forEach
            val intervalMonths = INTERVAL_MONTHS[pattern.interval] ?: return@forEach
            if (intervalMonths == 0) return@forEach // skip weekly

            cal.time = nextDue
            for (i in 0 until 12) {
                val date = cal.time
                if (date.after(Date()) || i == 0) {
                    result.add(FuturePayment(
                        date = date,
                        merchant = pattern.merchant,
                        amount = pattern.amount,
                        category = pattern.category,
                        interval = pattern.interval,
                        monthKey = monthSdf.format(date),
                    ))
                }
                cal.add(Calendar.MONTH, intervalMonths)
            }
        }

        result.sortBy { it.date }
        result
    }

    val grouped = payments.groupBy { it.monthKey }.toSortedMap()
    val next30Total = payments.filter {
        val diff = it.date.time - System.currentTimeMillis()
        diff in 0..30L * 24 * 60 * 60 * 1000
    }.sumOf { abs(it.amount) }

    val monthNames = DateFormatSymbols().months

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Next 30 days hero
        item {
            Box(modifier = Modifier.fillMaxWidth().wimgHero()) {
                Column(modifier = Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Nächste 30 Tage", style = MaterialTheme.typography.labelMedium, color = WimgColors.heroText.copy(alpha = 0.7f))
                    Spacer(Modifier.height(4.dp))
                    Text(formatAmountShort(next30Total), fontSize = 32.sp, fontWeight = FontWeight.Black, color = WimgColors.heroText)
                }
            }
        }

        // Monthly groups
        grouped.forEach { (monthKey, monthPayments) ->
            val parts = monthKey.split("-")
            val monthIdx = (parts.getOrNull(1)?.toIntOrNull() ?: 1) - 1
            val year = parts.getOrNull(0) ?: ""
            val monthTotal = monthPayments.sumOf { abs(it.amount) }

            item(key = "month_$monthKey") {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        "${monthNames.getOrElse(monthIdx) { "" }} $year",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        formatAmountShort(monthTotal),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            items(monthPayments, key = { "${it.merchant}_${it.date.time}" }) { payment ->
                val category = WimgCategory.fromId(payment.category)
                val dayFmt = SimpleDateFormat("d. MMM", Locale.getDefault())

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .wimgCard(WimgShapes.small)
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(category.color.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(category.icon, null, tint = category.color, modifier = Modifier.size(18.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(payment.merchant, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
                        Text(dayFmt.format(payment.date), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(formatAmountShort(abs(payment.amount)), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                }
            }
        }

        if (payments.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                    Text("Keine zukünftigen Zahlungen", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
            modifier = Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(category.color.copy(alpha = 0.12f)),
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
