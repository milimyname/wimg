package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgHero

@Composable
fun TaxScreen() {
    // Pendlerpauschale
    var km by remember { mutableStateOf("30") }
    var workDays by remember { mutableStateOf("220") }

    // Homeoffice
    var homeofficeDays by remember { mutableStateOf("100") }

    val kmVal = km.toDoubleOrNull() ?: 0.0
    val workDaysVal = workDays.toIntOrNull() ?: 0
    val homeofficeDaysVal = (homeofficeDays.toIntOrNull() ?: 0).coerceAtMost(210)

    // Pendlerpauschale calculation (§9 EStG)
    val first20km = kmVal.coerceAtMost(20.0) * 0.30
    val beyond20km = (kmVal - 20.0).coerceAtLeast(0.0) * 0.38
    val pendlerDaily = first20km + beyond20km
    val pendlerpauschale = pendlerDaily * workDaysVal

    // Homeoffice (6€/day, max 210 days)
    val homeofficePauschale = homeofficeDaysVal * 6.0

    val total = pendlerpauschale + homeofficePauschale

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Summary hero
        item {
            Box(modifier = Modifier.fillMaxWidth().wimgHero()) {
                Column(modifier = Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Gesamtabzug", style = MaterialTheme.typography.labelMedium, color = WimgColors.heroText.copy(alpha = 0.7f))
                    Spacer(Modifier.height(4.dp))
                    Text(formatAmountShort(total), fontSize = 32.sp, fontWeight = FontWeight.Black, color = WimgColors.heroText)
                }
            }
        }

        // Stats row
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TaxStatCard("Pendler", pendlerpauschale, Modifier.weight(1f))
                TaxStatCard("Homeoffice", homeofficePauschale, Modifier.weight(1f))
                TaxStatCard("Gesamt", total, Modifier.weight(1f))
            }
        }

        // Pendlerpauschale
        item {
            Card(shape = WimgShapes.medium, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(20.dp)) {
                    Text("Pendlerpauschale", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    Text("§9 EStG — Entfernungspauschale", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(16.dp))
                    OutlinedTextField(
                        value = km, onValueChange = { km = it },
                        label = { Text("Entfernung (km, einfach)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = workDays, onValueChange = { workDays = it },
                        label = { Text("Arbeitstage pro Jahr") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "0,30 €/km (erste 20 km) + 0,38 €/km (ab 21 km)",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        formatAmountShort(pendlerpauschale),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }

        // Homeoffice
        item {
            Card(shape = WimgShapes.medium, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(20.dp)) {
                    Text("Homeoffice-Pauschale", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    Text("§4 Abs. 5 Nr. 6c EStG", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(16.dp))
                    OutlinedTextField(
                        value = homeofficeDays, onValueChange = { homeofficeDays = it },
                        label = { Text("Homeoffice-Tage (max. 210)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(12.dp))
                    Text("6 €/Tag × $homeofficeDaysVal Tage", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(4.dp))
                    Text(formatAmountShort(homeofficePauschale), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun TaxStatCard(label: String, value: Double, modifier: Modifier = Modifier) {
    Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), modifier = modifier) {
        Column(modifier = Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Text(formatAmountShort(value), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
        }
    }
}
