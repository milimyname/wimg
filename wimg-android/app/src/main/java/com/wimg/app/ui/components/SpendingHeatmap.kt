package com.wimg.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.wimg.app.models.Snapshot
import java.text.DateFormatSymbols
import kotlin.math.abs

/**
 * GitHub-style spending heatmap showing monthly expenses from snapshots.
 * Indigo color scale from light (low) to dark (high).
 */
@Composable
fun SpendingHeatmap(
    snapshots: List<Snapshot>,
    modifier: Modifier = Modifier,
) {
    if (snapshots.size < 2) return

    val expenses = snapshots.map { abs(it.expenses) }
    val maxExpense = expenses.maxOrNull() ?: 1.0
    val months = DateFormatSymbols().shortMonths

    Column(modifier = modifier) {
        Text(
            "Ausgaben-Heatmap",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(8.dp))

        // Month labels
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            snapshots.takeLast(12).forEach { s ->
                val monthIdx = s.date.substring(5, 7).toIntOrNull()?.minus(1) ?: 0
                Text(
                    months.getOrElse(monthIdx) { "" },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Spacer(Modifier.height(4.dp))

        // Heatmap cells
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(32.dp),
        ) {
            val cellCount = snapshots.size.coerceAtMost(12)
            val cellWidth = size.width / cellCount
            val gap = 4f

            snapshots.takeLast(12).forEachIndexed { i, snapshot ->
                val intensity = if (maxExpense > 0) abs(snapshot.expenses) / maxExpense else 0.0
                val color = Color(
                    red = (0.224f * (1 - intensity.toFloat()) + 0.263f * intensity.toFloat()),
                    green = (0.224f * (1 - intensity.toFloat()) + 0.290f * intensity.toFloat()),
                    blue = (0.247f * (1 - intensity.toFloat()) + 0.910f * intensity.toFloat()),
                    alpha = 0.15f + 0.85f * intensity.toFloat(),
                )
                drawRoundRect(
                    color = color,
                    topLeft = Offset(i * cellWidth + gap / 2, 0f),
                    size = Size(cellWidth - gap, size.height),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(8f, 8f),
                )
            }
        }
    }
}
