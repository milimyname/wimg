package com.wimg.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.ArrowDropUp
import androidx.compose.material.icons.outlined.PieChart
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.CategoryBreakdown
import com.wimg.app.models.MonthlySummary
import com.wimg.app.models.Snapshot
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.InfoTooltip
import com.wimg.app.ui.components.MonthPicker
import com.wimg.app.ui.components.SpendingHeatmap
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import java.util.Calendar
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.roundToInt
import kotlin.math.sqrt
import com.wimg.app.i18n.L

@Composable
fun AnalysisScreen(selectedAccount: String?, navController: androidx.navigation.NavController? = null) {
    val calendar = Calendar.getInstance()
    var year by remember { mutableIntStateOf(calendar.get(Calendar.YEAR)) }
    var month by remember { mutableIntStateOf(calendar.get(Calendar.MONTH) + 1) }
    var summary by remember { mutableStateOf<MonthlySummary?>(null) }
    var prevSummary by remember { mutableStateOf<MonthlySummary?>(null) }
    var snapshots by remember { mutableStateOf<List<Snapshot>>(emptyList()) }
    var hasAnyData by remember { mutableStateOf(true) }
    var expandedCategory by remember { mutableStateOf<Int?>(null) }
    var allTransactions by remember { mutableStateOf<List<com.wimg.app.models.Transaction>>(emptyList()) }

    LaunchedEffect(year, month, selectedAccount) {
        summary = LibWimg.getSummaryFiltered(year, month, selectedAccount)
        val pm = if (month == 1) 12 else month - 1
        val py = if (month == 1) year - 1 else year
        prevSummary = LibWimg.getSummaryFiltered(py, pm, selectedAccount)
        snapshots = LibWimg.getSnapshots()
        hasAnyData = LibWimg.getTransactions().isNotEmpty()
        allTransactions = LibWimg.getTransactionsFiltered(selectedAccount)
    }

    val categories = summary?.by_category?.filter { it.id != 10 && it.id != 11 }?.sortedByDescending { abs(it.amount) } ?: emptyList()
    val totalExpenses = abs(summary?.expenses ?: 0.0)
    val prevTotalExpenses = abs(prevSummary?.expenses ?: 0.0)
    val monthDelta: Int? = if (prevTotalExpenses == 0.0) null
        else (((totalExpenses - prevTotalExpenses) / prevTotalExpenses) * 100).roundToInt()

    // Empty state — no transactions imported at all
    if (!hasAnyData) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .padding(horizontal = 32.dp, vertical = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(40.dp))
            Box(
                modifier = Modifier
                    .size(112.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(WimgColors.accent.copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.PieChart,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.size(40.dp),
                )
            }
            Spacer(Modifier.height(24.dp))
            Text(
                L("Noch keine Daten"),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                L("Importiere eine CSV-Datei, um deine Ausgaben zu analysieren."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            Spacer(Modifier.height(24.dp))
            Button(
                onClick = { navController?.navigate("import") },
                colors = ButtonDefaults.buttonColors(
                    containerColor = WimgColors.accent,
                    contentColor = WimgColors.heroText,
                ),
                shape = WimgShapes.small,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(L("CSV importieren"), fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }
        }
        return
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

        if (categories.isNotEmpty()) {
            // Section header for donut
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L("Ausgaben nach Kategorie"),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Black,
                    )
                    InfoTooltip(L("Zeigt deine Ausgaben des Monats aufgeschlüsselt nach Kategorie. Tippe ein Segment für Details."))
                }
            }

            // Donut hero card with center overlay + Income/Available split
            item {
                DonutHeroCard(
                    categories = categories,
                    totalExpenses = totalExpenses,
                    income = summary?.income ?: 0.0,
                    available = summary?.available ?: 0.0,
                    monthDelta = monthDelta,
                )
            }

            // Net worth + heatmap
            if (snapshots.size >= 2) {
                item { NetWorthCard(snapshots) }
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

            // Categories header
            item {
                Row(
                    modifier = Modifier.padding(top = 8.dp).fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            L("Kategorien"),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Black,
                        )
                        InfoTooltip(L("Alle Ausgabenkategorien dieses Monats, absteigend nach Betrag. Tippe eine Kategorie für ihre Transaktionen."))
                    }
                    Text(
                        L("vs. Vormonat"),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .clip(RoundedCornerShape(20.dp))
                            .background(MaterialTheme.colorScheme.surface)
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                }
            }

            // Category cards with delta vs. previous month + drill-down
            items(categories, key = { it.id }) { cat ->
                val prevAmt = prevSummary?.by_category?.firstOrNull { it.id == cat.id }?.amount ?: 0.0
                val pct = if (totalExpenses > 0) abs(cat.amount) / totalExpenses else 0.0
                val delta: Int? = if (prevAmt == 0.0) null
                    else (((abs(cat.amount) - abs(prevAmt)) / abs(prevAmt)) * 100).roundToInt()
                CategoryBreakdownRow(
                    cat = cat,
                    pct = pct,
                    delta = delta,
                    expanded = expandedCategory == cat.id,
                    onClick = {
                        expandedCategory = if (expandedCategory == cat.id) null else cat.id
                    },
                    drilldownTx = if (expandedCategory == cat.id) {
                        val prefix = String.format("%04d-%02d", year, month)
                        allTransactions.filter { it.date.startsWith(prefix) && it.category == cat.id }
                    } else emptyList(),
                )
            }
        } else {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 64.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("📊", fontSize = 32.sp)
                    Spacer(Modifier.height(12.dp))
                    Text(L("Keine Daten"), fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
                    Text(
                        L("Für diesen Monat liegen keine Ausgaben vor"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun CategoryBreakdownRow(
    cat: CategoryBreakdown,
    pct: Double,
    delta: Int?,
    expanded: Boolean,
    onClick: () -> Unit,
    drilldownTx: List<com.wimg.app.models.Transaction>,
) {
    val category = WimgCategory.fromId(cat.id)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .wimgCard(WimgShapes.large)
            .clickable(onClick = onClick)
            .padding(20.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(category.color.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(category.icon, null, tint = category.color, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(L(category.label), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    "${(pct * 100).toInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    formatAmountShort(cat.amount),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.ExtraBold,
                )
                if (delta != null) {
                    val color = when {
                        delta < 0 -> Color(0xFF059669)
                        delta > 0 -> Color(0xFFE11D48)
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "${if (delta > 0) "+" else ""}$delta%",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = color,
                        )
                        Spacer(Modifier.width(2.dp))
                        if (delta != 0) {
                            Icon(
                                if (delta < 0) Icons.Outlined.ArrowDropDown else Icons.Outlined.ArrowDropUp,
                                null,
                                tint = color,
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        LinearProgressIndicator(
            progress = { pct.toFloat() },
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(5.dp)),
            color = category.color,
            trackColor = Color(0xFFE5E7EB),
        )

        if (expanded) {
            Spacer(Modifier.height(12.dp))
            if (drilldownTx.isEmpty()) {
                Text(
                    L("Keine Transaktionen"),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                drilldownTx.take(20).forEach { tx ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            tx.description,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            modifier = Modifier.weight(1f).padding(end = 12.dp),
                        )
                        Text(
                            formatAmountShort(abs(tx.amount)),
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Donut Hero Card

@Composable
private fun DonutHeroCard(
    categories: List<CategoryBreakdown>,
    totalExpenses: Double,
    income: Double,
    available: Double,
    monthDelta: Int?,
) {
    var selected by remember { mutableStateOf<Int?>(null) }
    val selectedCat = selected?.let { id -> categories.firstOrNull { it.id == id } }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = WimgShapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier.size(220.dp),
                contentAlignment = Alignment.Center,
            ) {
                DonutChart(
                    categories = categories,
                    selectedId = selected,
                    onSelect = { id -> selected = if (selected == id) null else id },
                    modifier = Modifier.fillMaxSize(),
                )
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (selectedCat != null) {
                        val cat = WimgCategory.fromId(selectedCat.id)
                        Icon(
                            cat.icon,
                            contentDescription = null,
                            tint = cat.color,
                            modifier = Modifier.size(22.dp),
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            L(cat.label),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = cat.color,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            formatAmountShort(abs(selectedCat.amount)),
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Black,
                        )
                        val pct = if (totalExpenses > 0) (abs(selectedCat.amount) / totalExpenses * 100).roundToInt() else 0
                        Text(
                            "$pct%",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        Text(
                            L("Ausgaben").uppercase(),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            formatAmountShort(totalExpenses),
                            fontSize = 26.sp,
                            fontWeight = FontWeight.Black,
                        )
                        if (monthDelta != null) {
                            Spacer(Modifier.height(6.dp))
                            val color = when {
                                monthDelta < 0 -> Color(0xFF059669)
                                monthDelta > 0 -> Color(0xFFE11D48)
                                else -> MaterialTheme.colorScheme.onSurfaceVariant
                            }
                            Row(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(20.dp))
                                    .background(color.copy(alpha = 0.08f))
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                if (monthDelta != 0) {
                                    Icon(
                                        if (monthDelta < 0) Icons.Outlined.ArrowDropDown else Icons.Outlined.ArrowDropUp,
                                        null,
                                        tint = color,
                                        modifier = Modifier.size(14.dp),
                                    )
                                    Spacer(Modifier.width(2.dp))
                                }
                                Text(
                                    "${kotlin.math.abs(monthDelta)}%",
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = color,
                                )
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Income / Available split row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(MaterialTheme.colorScheme.background)
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        L("Einnahmen").uppercase(),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        formatAmountShort(income),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.ExtraBold,
                        color = Color(0xFF059669),
                    )
                }
                Box(
                    modifier = Modifier
                        .width(1.dp)
                        .height(36.dp)
                        .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.3f)),
                )
                Column(
                    modifier = Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        L("Verfügbar").uppercase(),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        formatAmountShort(kotlin.math.abs(available)),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.ExtraBold,
                        color = if (available >= 0) Color(0xFF059669) else Color(0xFFE11D48),
                    )
                }
            }
        }
    }
}

// MARK: - Donut Chart

@Composable
private fun DonutChart(
    categories: List<CategoryBreakdown>,
    selectedId: Int?,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val total = categories.sumOf { abs(it.amount) }.toFloat()
    Canvas(
        modifier = modifier.pointerInput(categories) {
            detectTapGestures { offset ->
                if (total <= 0f) return@detectTapGestures
                val w = size.width.toFloat()
                val h = size.height.toFloat()
                val minDim = if (w < h) w else h
                val stroke = minDim * 0.18f
                val outerR = minDim / 2f
                val innerR = outerR - stroke
                val cx = w / 2f
                val cy = h / 2f
                val dx = offset.x - cx
                val dy = offset.y - cy
                val dist = sqrt(dx * dx + dy * dy)
                // Only react to taps that land inside the donut ring itself.
                if (dist < innerR || dist > outerR) return@detectTapGestures
                // atan2(dy, dx) → angle CCW from +x; rotate so 0° points up,
                // then convert to clockwise so it matches the draw direction.
                var angle = (atan2(dy, dx) * 180f / PI.toFloat()) + 90f
                angle = ((angle % 360f) + 360f) % 360f
                var cumulative = 0f
                for (cat in categories) {
                    val sweep = (abs(cat.amount).toFloat() / total) * 360f
                    if (angle < cumulative + sweep) {
                        onSelect(cat.id)
                        return@detectTapGestures
                    }
                    cumulative += sweep
                }
            }
        },
    ) {
        val stroke = size.minDimension * 0.18f
        val radius = (size.minDimension - stroke) / 2f
        val topLeft = Offset(
            (size.width - radius * 2f) / 2f,
            (size.height - radius * 2f) / 2f,
        )
        val arcSize = Size(radius * 2f, radius * 2f)
        var start = -90f
        if (total <= 0f) {
            drawArc(
                color = Color(0xFFE5E7EB),
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Butt),
            )
            return@Canvas
        }
        categories.forEach { cat ->
            val sweep = (abs(cat.amount).toFloat() / total) * 360f
            val isDim = selectedId != null && selectedId != cat.id
            drawArc(
                color = WimgCategory.fromId(cat.id).color.copy(alpha = if (isDim) 0.35f else 1f),
                startAngle = start,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Butt),
            )
            start += sweep
        }
    }
}

// MARK: - Net Worth Card

@Composable
private fun NetWorthCard(snapshots: List<Snapshot>) {
    val latest = snapshots.last()
    val first = snapshots.first()
    val growth = latest.net_worth - first.net_worth
    val growthPct: Int? = if (first.net_worth == 0.0) null
        else ((growth / kotlin.math.abs(first.net_worth)) * 100).roundToInt()

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = WimgShapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L("Vermögen"),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Black,
                    )
                    InfoTooltip(L("Kumulatives Nettovermögen über die Zeit, berechnet aus monatlichen Snapshots (Einnahmen − Ausgaben). Mindestens 2 Snapshots erforderlich."))
                }
                if (growthPct != null) {
                    val color = if (growthPct >= 0) Color(0xFF059669) else Color(0xFFE11D48)
                    Text(
                        "${if (growthPct >= 0) "+" else ""}$growthPct% ${L("vs. Vormonat")}",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = color,
                        modifier = Modifier
                            .clip(RoundedCornerShape(20.dp))
                            .background(color.copy(alpha = 0.08f))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                formatAmountShort(latest.net_worth),
                fontSize = 32.sp,
                fontWeight = FontWeight.Black,
            )
        }
    }
}
