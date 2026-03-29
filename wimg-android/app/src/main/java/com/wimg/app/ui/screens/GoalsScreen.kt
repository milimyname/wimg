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
import com.wimg.app.models.Goal
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgHero
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
private data class GoalInput(val id: String, val name: String, val icon: String, val target: Double, val deadline: String? = null)

private val GOAL_ICONS = listOf("🎯", "🏠", "✈️", "🚗", "💻", "📱", "🎓", "💍", "🏖️", "🎸", "📷", "⚽")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalsScreen() {
    var goals by remember { mutableStateOf<List<Goal>>(emptyList()) }
    var showAdd by remember { mutableStateOf(false) }
    var contributeGoal by remember { mutableStateOf<Goal?>(null) }

    fun reload() {
        val str = com.wimg.app.bridge.WimgJni.nativeGetGoals() ?: return
        goals = Json { ignoreUnknownKeys = true }.decodeFromString(str)
    }

    LaunchedEffect(Unit) { reload() }

    val totalSaved = goals.sumOf { it.current }
    val totalTarget = goals.sumOf { it.target }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAdd = true },
                containerColor = WimgColors.accent,
                contentColor = WimgColors.heroText,
            ) {
                Icon(Icons.Outlined.Add, "Sparziel hinzufügen")
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
            if (goals.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("🎯", fontSize = 48.sp)
                            Spacer(Modifier.height(8.dp))
                            Text("Keine Sparziele", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            Text("Tippe + um ein Sparziel zu erstellen", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            } else {
                // Hero
                item {
                    Box(modifier = Modifier.fillMaxWidth().wimgHero()) {
                        Column(modifier = Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(formatAmountShort(totalSaved), fontSize = 32.sp, fontWeight = FontWeight.Black, color = WimgColors.heroText)
                            Text("von ${formatAmountShort(totalTarget)} gespart", style = MaterialTheme.typography.bodySmall, color = WimgColors.heroText.copy(alpha = 0.7f))
                            if (totalTarget > 0) {
                                Spacer(Modifier.height(8.dp))
                                LinearProgressIndicator(
                                    progress = { (totalSaved / totalTarget).toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                                    color = WimgColors.heroText,
                                    trackColor = WimgColors.heroText.copy(alpha = 0.2f),
                                )
                            }
                        }
                    }
                }

                items(goals, key = { it.id }) { goal ->
                    GoalRow(goal, onContribute = { contributeGoal = goal }, onDelete = {
                        com.wimg.app.bridge.WimgJni.nativeDeleteGoal(goal.id)
                        reload()
                    })
                }
            }
        }
    }

    if (showAdd) {
        AddGoalSheet(onDismiss = { showAdd = false }, onAdd = { name, icon, target ->
            val id = java.util.UUID.randomUUID().toString()
            val json = Json.encodeToString(GoalInput.serializer(), GoalInput(id, name, icon, target))
            com.wimg.app.bridge.WimgJni.nativeAddGoal(json)
            reload()
            showAdd = false
        })
    }

    contributeGoal?.let { goal ->
        ContributeSheet(goal, onDismiss = { contributeGoal = null }, onContribute = { amountCents ->
            com.wimg.app.bridge.WimgJni.nativeContributeGoal(goal.id, amountCents)
            reload()
            contributeGoal = null
        })
    }
}

@Composable
private fun GoalRow(goal: Goal, onContribute: () -> Unit, onDelete: () -> Unit) {
    val pct = if (goal.target > 0) goal.current / goal.target else 0.0
    Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(goal.icon, fontSize = 24.sp)
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(goal.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    Text("${formatAmountShort(goal.current)} von ${formatAmountShort(goal.target)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("${(pct * 100).toInt()}%", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
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
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onContribute) { Text("Einzahlen") }
                TextButton(onClick = onDelete) { Text("Löschen", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddGoalSheet(onDismiss: () -> Unit, onAdd: (String, String, Double) -> Unit) {
    var name by remember { mutableStateOf("") }
    var icon by remember { mutableStateOf("🎯") }
    var target by remember { mutableStateOf("") }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text("Sparziel erstellen", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            // Icon picker
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GOAL_ICONS.forEach { ic ->
                    TextButton(onClick = { icon = ic }) {
                        Text(ic, fontSize = if (icon == ic) 28.sp else 20.sp)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(value = target, onValueChange = { target = it }, label = { Text("Zielbetrag (€)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = { onAdd(name, icon, target.toDoubleOrNull() ?: 0.0) },
                enabled = name.isNotBlank() && (target.toDoubleOrNull() ?: 0.0) > 0,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
            ) {
                Text("Erstellen", fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ContributeSheet(goal: Goal, onDismiss: () -> Unit, onContribute: (Long) -> Unit) {
    var amount by remember { mutableStateOf("") }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text("${goal.icon} ${goal.name}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            OutlinedTextField(value = amount, onValueChange = { amount = it }, label = { Text("Betrag (€)") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = { onContribute(((amount.toDoubleOrNull() ?: 0.0) * 100).toLong()) },
                enabled = (amount.toDoubleOrNull() ?: 0.0) > 0,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
            ) {
                Text("Einzahlen", fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
