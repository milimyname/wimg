package com.wimg.app.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.DateFormatSymbols

@Composable
fun MonthPicker(
    year: Int,
    month: Int,
    onChanged: (year: Int, month: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val monthNames = DateFormatSymbols().shortMonths

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = {
            if (month == 1) onChanged(year - 1, 12)
            else onChanged(year, month - 1)
        }) {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                contentDescription = "Vorheriger Monat",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Text(
            "${monthNames[month - 1]} $year",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 16.dp),
        )

        IconButton(onClick = {
            if (month == 12) onChanged(year + 1, 1)
            else onChanged(year, month + 1)
        }) {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Nächster Monat",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
