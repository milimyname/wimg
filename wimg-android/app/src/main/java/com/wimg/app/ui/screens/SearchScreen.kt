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
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import kotlin.math.abs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(selectedAccount: String?) {
    var query by remember { mutableStateOf("") }
    var transactions by remember { mutableStateOf<List<Transaction>>(emptyList()) }
    var selectedCategories by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var amountMin by remember { mutableFloatStateOf(0f) }
    var amountMax by remember { mutableFloatStateOf(1000f) }
    var selectedTx by remember { mutableStateOf<Transaction?>(null) }

    LaunchedEffect(selectedAccount) {
        transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
    }

    val filtered = transactions.filter { tx ->
        val matchesQuery = query.isBlank() || tx.description.contains(query, ignoreCase = true)
        val matchesCat = selectedCategories.isEmpty() || selectedCategories.contains(tx.category)
        val matchesAmount = abs(tx.amount) >= amountMin && (amountMax >= 1000 || abs(tx.amount) <= amountMax)
        matchesQuery && matchesCat && matchesAmount && !tx.isExcluded
    }

    val grouped = filtered.groupBy { it.date }.toSortedMap(compareByDescending { it })
    val hasFilters = selectedCategories.isNotEmpty() || amountMin > 0 || amountMax < 1000

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
            keyboardActions = KeyboardActions.Default,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            shape = RoundedCornerShape(16.dp),
        )

        // Category filter chips
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
                    leadingIcon = if (selected) {
                        { Icon(cat.icon, contentDescription = null, modifier = Modifier.size(16.dp)) }
                    } else null,
                )
            }
        }

        // Active filter chips
        if (hasFilters) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(bottom = 8.dp),
            ) {
                if (selectedCategories.isNotEmpty()) {
                    item {
                        AssistChip(
                            onClick = { selectedCategories = emptySet() },
                            label = { Text("${selectedCategories.size} Kategorien ✕") },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = WimgColors.accent,
                                labelColor = WimgColors.heroText,
                            ),
                        )
                    }
                }
                if (amountMin > 0 || amountMax < 1000) {
                    item {
                        AssistChip(
                            onClick = { amountMin = 0f; amountMax = 1000f },
                            label = { Text("${amountMin.toInt()}–${if (amountMax >= 1000) "∞" else amountMax.toInt().toString()} € ✕") },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = WimgColors.accent,
                                labelColor = WimgColors.heroText,
                            ),
                        )
                    }
                }
            }
        }

        // Results
        if (query.isBlank() && !hasFilters) {
            // Empty state — prompt to search
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("🔍", fontSize = 48.sp)
                    Spacer(Modifier.height(8.dp))
                    Text("Suche starten", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("Tippe oben um Transaktionen zu finden", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else if (grouped.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Keine Ergebnisse", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                item {
                    Text(
                        "${filtered.size} Ergebnisse",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                }
                grouped.forEach { (date, txs) ->
                    item(key = "h_$date") {
                        Text(
                            date,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 8.dp),
                        )
                    }
                    items(txs, key = { it.id }) { tx ->
                        val category = WimgCategory.fromId(tx.category)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .wimgCard(WimgShapes.small)
                                .clickable { selectedTx = tx }
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
                }
            }
        }
    }

    selectedTx?.let { tx ->
        CategoryEditorSheet(transaction = tx, onDismiss = {
            selectedTx = null
            // Reload
            transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
        })
    }
}
