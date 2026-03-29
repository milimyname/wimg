package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.Debt
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgHero
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
private data class DebtInput(val id: String, val name: String, val total: Double, val monthly: Double)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DebtsScreen() {
    var debts by remember { mutableStateOf<List<Debt>>(emptyList()) }
    var showAdd by remember { mutableStateOf(false) }
    var showPay by remember { mutableStateOf<Debt?>(null) }

    fun reload() { debts = LibWimg.getDebts() }

    LaunchedEffect(Unit) { reload() }

    val totalDebt = debts.sumOf { it.total }
    val totalPaid = debts.sumOf { it.paid }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAdd = true },
                containerColor = WimgColors.accent,
                contentColor = WimgColors.heroText,
            ) {
                Icon(Icons.Outlined.Add, "Schuld hinzufügen")
            }
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (debts.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("💰", fontSize = 48.sp)
                            Spacer(Modifier.height(8.dp))
                            Text("Keine Schulden", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            Text("Tippe + um eine Schuld hinzuzufügen", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            } else {
                // Hero
                item {
                    Box(modifier = Modifier.fillMaxWidth().wimgHero()) {
                        Column(modifier = Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Verbleibend", style = MaterialTheme.typography.labelMedium, color = WimgColors.heroText.copy(alpha = 0.7f))
                            Spacer(Modifier.height(4.dp))
                            Text(formatAmountShort(totalDebt - totalPaid), fontSize = 32.sp, fontWeight = FontWeight.Black, color = WimgColors.heroText)
                            if (totalDebt > 0) {
                                Spacer(Modifier.height(8.dp))
                                LinearProgressIndicator(
                                    progress = { (totalPaid / totalDebt).toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                                    color = WimgColors.heroText,
                                    trackColor = WimgColors.heroText.copy(alpha = 0.2f),
                                )
                            }
                        }
                    }
                }

                items(debts, key = { it.id }) { debt ->
                    DebtRow(debt, onPay = { showPay = debt }, onDelete = {
                        try { LibWimg.deleteDebt(debt.id) } catch (_: Exception) {}
                        reload()
                    })
                }
            }
        }
    }

    // Add debt sheet
    if (showAdd) {
        AddDebtSheet(onDismiss = { showAdd = false }, onAdd = { name, total, monthly ->
            val id = java.util.UUID.randomUUID().toString()
            val json = Json.encodeToString(DebtInput.serializer(), DebtInput(id, name, total, monthly))
            try {
                LibWimg.addDebt(json)
            } catch (_: Exception) {}
            reload()
            showAdd = false
        })
    }

    // Pay sheet
    showPay?.let { debt ->
        PayDebtSheet(debt, onDismiss = { showPay = null }, onPay = { amountCents ->
            try { LibWimg.markDebtPaid(debt.id, amountCents) } catch (_: Exception) {}
            reload()
            showPay = null
        })
    }
}

@Composable
private fun DebtRow(debt: Debt, onPay: () -> Unit, onDelete: () -> Unit) {
    val pct = if (debt.total > 0) debt.paid / debt.total else 0.0
    Card(
        shape = WimgShapes.small,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(debt.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Text("${(pct * 100).toInt()}%", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { pct.toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                color = WimgColors.accent,
                trackColor = WimgColors.accent.copy(alpha = 0.15f),
            )
            Spacer(Modifier.height(8.dp))
            Row {
                Text(
                    "${formatAmountShort(debt.paid)} / ${formatAmountShort(debt.total)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = onPay) { Text("Zahlen") }
                TextButton(onClick = onDelete) { Text("Löschen", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddDebtSheet(onDismiss: () -> Unit, onAdd: (String, Double, Double) -> Unit) {
    var name by remember { mutableStateOf("") }
    var total by remember { mutableStateOf("") }
    var monthly by remember { mutableStateOf("") }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text("Schuld hinzufügen", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(value = total, onValueChange = { total = it }, label = { Text("Gesamtbetrag (€)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(value = monthly, onValueChange = { monthly = it }, label = { Text("Monatliche Rate (€)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = { onAdd(name, total.toDoubleOrNull() ?: 0.0, monthly.toDoubleOrNull() ?: 0.0) },
                enabled = name.isNotBlank() && (total.toDoubleOrNull() ?: 0.0) > 0,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
            ) {
                Text("Hinzufügen", fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PayDebtSheet(debt: Debt, onDismiss: () -> Unit, onPay: (Long) -> Unit) {
    var amount by remember { mutableStateOf("") }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text("Zahlung: ${debt.name}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            OutlinedTextField(value = amount, onValueChange = { amount = it }, label = { Text("Betrag (€)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = { onPay(((amount.toDoubleOrNull() ?: 0.0) * 100).toLong()) },
                enabled = (amount.toDoubleOrNull() ?: 0.0) > 0,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
            ) {
                Text("Zahlen", fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

// Add missing function to LibWimg
private fun LibWimg.addDebt(json: String) {
    val rc = com.wimg.app.bridge.WimgJni.nativeAddDebt(json)
    if (rc != 0) throw com.wimg.app.bridge.WimgException("addDebt failed")
}

private fun LibWimg.deleteDebt(id: String) {
    val rc = com.wimg.app.bridge.WimgJni.nativeDeleteDebt(id)
    if (rc != 0) throw com.wimg.app.bridge.WimgException("deleteDebt failed")
}

private fun LibWimg.markDebtPaid(id: String, amountCents: Long) {
    val rc = com.wimg.app.bridge.WimgJni.nativeMarkDebtPaid(id, amountCents)
    if (rc != 0) throw com.wimg.app.bridge.WimgException("markDebtPaid failed")
}

private fun LibWimg.getDebts(): List<Debt> {
    val str = com.wimg.app.bridge.WimgJni.nativeGetDebts() ?: return emptyList()
    return kotlinx.serialization.json.Json { ignoreUnknownKeys = true }.decodeFromString(str)
}
