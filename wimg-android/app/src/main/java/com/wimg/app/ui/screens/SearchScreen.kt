package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.bridge.WimgJni
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import kotlin.math.abs

@Composable
fun SearchScreen(selectedAccount: String?, navController: NavController) {
    var query by remember { mutableStateOf("") }
    var transactions by remember { mutableStateOf<List<Transaction>>(emptyList()) }
    var selectedCategories by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var selectedTx by remember { mutableStateOf<Transaction?>(null) }
    var undoMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(selectedAccount) {
        transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
    }

    val isSearching = query.isNotBlank() || selectedCategories.isNotEmpty()

    val filtered = if (!isSearching) emptyList() else transactions.filter { tx ->
        val matchesQuery = query.isBlank() || tx.description.contains(query, ignoreCase = true)
        val matchesCat = selectedCategories.isEmpty() || selectedCategories.contains(tx.category)
        matchesQuery && matchesCat && !tx.isExcluded
    }

    val grouped = filtered.groupBy { it.date }.toSortedMap(compareByDescending { it })

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        // Search bar
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("Transaktionen suchen...") },
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            trailingIcon = {
                if (query.isNotEmpty()) {
                    IconButton(onClick = { query = "" }) {
                        Icon(Icons.Outlined.Close, contentDescription = "Löschen")
                    }
                }
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            shape = RoundedCornerShape(16.dp),
        )

        // Category filter chips
        if (isSearching) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(bottom = 8.dp),
            ) {
                val categories = listOf(
                    WimgCategory.GROCERIES, WimgCategory.DINING, WimgCategory.TRANSPORT,
                    WimgCategory.SHOPPING, WimgCategory.ENTERTAINMENT, WimgCategory.HOUSING,
                    WimgCategory.SUBSCRIPTIONS, WimgCategory.HEALTH,
                )
                items(categories) { cat ->
                    val selected = selectedCategories.contains(cat.id)
                    FilterChip(
                        selected = selected,
                        onClick = {
                            selectedCategories = if (selected) selectedCategories - cat.id
                            else selectedCategories + cat.id
                        },
                        label = { Text(cat.label, fontSize = 12.sp) },
                    )
                }
            }
        }

        if (isSearching) {
            // Search results
            if (grouped.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Keine Ergebnisse", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    item {
                        Text("${filtered.size} Ergebnisse", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 4.dp))
                    }
                    grouped.forEach { (date, txs) ->
                        item(key = "h_$date") {
                            Text(date, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 8.dp))
                        }
                        items(txs, key = { it.id }) { tx ->
                            SearchResultRow(tx) { selectedTx = tx }
                        }
                    }
                }
            }
        } else {
            // Quick actions (matching iOS SearchView)
            LazyColumn(
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                // Navigation
                item {
                    ActionSection("NAVIGATION") {
                        NavRow("Analyse", Icons.Outlined.BarChart, Color(0xFF5856D6)) { navController.navigate("analysis") }
                        NavRow("Schulden", Icons.Outlined.CreditCard, Color(0xFFFF2D55)) { navController.navigate("debts") }
                        NavRow("Sparziele", Icons.Outlined.Flag, Color(0xFFFFD60A)) { navController.navigate("goals") }
                        NavRow("Wiederkehrend", Icons.Outlined.Refresh, Color(0xFF30D158)) { navController.navigate("recurring") }
                        NavRow("Steuern", Icons.Outlined.Description, Color(0xFFFF9500)) { navController.navigate("tax") }
                        NavRow("Rückblick", Icons.Outlined.CalendarMonth, Color(0xFFAF52DE)) { navController.navigate("review") }
                        NavRow("Bankverbindung", Icons.Outlined.AccountBalance, Color(0xFF5AC8FA)) { navController.navigate("fints") }
                        NavRow("Import", Icons.Outlined.FileUpload, Color(0xFF007AFF)) { navController.navigate("import") }
                        NavRow("Einstellungen", Icons.Outlined.Settings, Color(0xFF8E8E93)) { navController.navigate("settings") }
                        NavRow("Über wimg", Icons.Outlined.Info, Color(0xFF8E8E93)) { navController.navigate("about") }
                        NavRow("Feedback senden", Icons.Outlined.ChatBubbleOutline, Color(0xFF5856D6)) { navController.navigate("feedback") }
                    }
                }

                // Categorization
                item {
                    ActionSection("KATEGORISIERUNG") {
                        ActionRow("Auto-Kategorisieren", Icons.Outlined.Label, Color(0xFFFF9500)) {
                            val n = LibWimg.autoCategorize()
                            undoMessage = if (n > 0) "$n kategorisiert" else "Keine neuen Kategorien"
                            transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
                        }
                        ActionRow("Wiederkehrende erkennen", Icons.Outlined.Refresh, Color(0xFF30D158)) {
                            val n = LibWimg.detectRecurring()
                            undoMessage = if (n > 0) "$n Muster erkannt" else "Keine neuen Muster"
                        }
                    }
                }

                // Data
                item {
                    ActionSection("DATEN") {
                        ActionRow("Snapshot erstellen", Icons.Outlined.CameraAlt, Color(0xFF007AFF)) {
                            val cal = java.util.Calendar.getInstance()
                            try { LibWimg.takeSnapshot(cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1) } catch (_: Exception) {}
                            undoMessage = "Snapshot erstellt"
                        }
                        ActionRow("CSV exportieren", Icons.Outlined.FileUpload, Color(0xFF5856D6)) {
                            // TODO: share export
                            undoMessage = "Export wird vorbereitet..."
                        }
                    }
                }

                // Undo/Redo
                item {
                    ActionSection("BEARBEITEN") {
                        ActionRow("Rückgängig", Icons.Outlined.Undo, Color(0xFF8E8E93)) {
                            val result = LibWimg.undo()
                            if (result != null) {
                                undoMessage = "Rückgängig: ${result.op} ${result.table}"
                                transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
                            }
                        }
                        ActionRow("Wiederherstellen", Icons.Outlined.Redo, Color(0xFF8E8E93)) {
                            val result = LibWimg.redo()
                            if (result != null) {
                                undoMessage = "Wiederhergestellt: ${result.op} ${result.table}"
                                transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
                            }
                        }
                    }
                }
            }
        }
    }

    // Undo snackbar
    undoMessage?.let { msg ->
        LaunchedEffect(msg) {
            kotlinx.coroutines.delay(3000)
            undoMessage = null
        }
    }

    // Category editor
    selectedTx?.let { tx ->
        CategoryEditorSheet(transaction = tx, onDismiss = {
            selectedTx = null
            transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
        })
    }
}

@Composable
private fun ActionSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Text(
            title,
            style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.8.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 4.dp, bottom = 10.dp),
        )
        Column(
            modifier = Modifier.wimgCard(),
            content = content,
        )
    }
}

@Composable
private fun NavRow(label: String, icon: ImageVector, color: Color, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(color.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(15.dp))
        }
        Spacer(Modifier.width(14.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f), modifier = Modifier.size(12.dp))
    }
}

@Composable
private fun ActionRow(label: String, icon: ImageVector, color: Color, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(color.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(15.dp))
        }
        Spacer(Modifier.width(14.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f), modifier = Modifier.size(12.dp))
    }
}

@Composable
private fun SearchResultRow(tx: Transaction, onClick: () -> Unit) {
    val category = WimgCategory.fromId(tx.category)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .wimgCard(WimgShapes.small)
            .clickable(onClick = onClick)
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
            Text(tx.description, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
            Text(category.label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            formatAmountShort(tx.amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = if (tx.isIncome) WimgCategory.INCOME.color else MaterialTheme.colorScheme.onSurface,
        )
    }
}
