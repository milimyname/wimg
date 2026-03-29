package com.wimg.app.ui.screens
import com.wimg.app.ui.components.TText

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard

enum class TxFilter(val label: String) {
    ALL("Alle"),
    EXPENSES("Ausgaben"),
    INCOME("Einnahmen"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionsScreen(selectedAccount: String?) {
    var transactions by remember { mutableStateOf<List<Transaction>>(emptyList()) }
    var filter by remember { mutableStateOf(TxFilter.ALL) }
    var selectedTx by remember { mutableStateOf<Transaction?>(null) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var filterCategories by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var searchText by remember { mutableStateOf("") }
    var amountMin by remember { mutableFloatStateOf(0f) }
    var amountMax by remember { mutableFloatStateOf(1000f) }

    fun reload() {
        transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
    }

    LaunchedEffect(selectedAccount) { reload() }

    val activeFilterCount = (if (filterCategories.isNotEmpty()) 1 else 0) +
        (if (searchText.isNotBlank()) 1 else 0) +
        (if (amountMin > 0 || amountMax < 1000) 1 else 0)

    val filtered = transactions.filter { tx ->
        val matchesFilter = when (filter) {
            TxFilter.ALL -> !tx.isExcluded
            TxFilter.EXPENSES -> tx.isExpense && !tx.isExcluded
            TxFilter.INCOME -> tx.isIncome && !tx.isExcluded
        }
        val matchesSearch = searchText.isBlank() || tx.description.contains(searchText, ignoreCase = true)
        val matchesCat = filterCategories.isEmpty() || filterCategories.contains(tx.category)
        val matchesAmount = kotlin.math.abs(tx.amount) >= amountMin && (amountMax >= 1000 || kotlin.math.abs(tx.amount) <= amountMax)
        matchesFilter && matchesSearch && matchesCat && matchesAmount
    }

    val grouped = filtered.groupBy { it.date }.toSortedMap(compareByDescending { it })

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        // Segmented filter + filter button
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            TxFilter.entries.forEach { f ->
                FilterChip(
                    selected = filter == f,
                    onClick = { filter = f },
                    label = { Text(f.label) },
                    modifier = Modifier.weight(1f),
                )
            }
            IconButton(onClick = { showFilterSheet = true }) {
                BadgedBox(
                    badge = {
                        if (activeFilterCount > 0) {
                            Badge(containerColor = WimgColors.accent) {
                                Text("$activeFilterCount", color = WimgColors.heroText, fontSize = 10.sp)
                            }
                        }
                    }
                ) {
                    Icon(
                        Icons.Outlined.FilterList,
                        contentDescription = "Filter",
                        tint = if (activeFilterCount > 0) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        if (grouped.isEmpty()) {
            // Empty state
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("📋", fontSize = 48.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Keine Umsätze",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        "Importiere eine CSV-Datei",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                grouped.forEach { (date, txs) ->
                    item(key = "header_$date") {
                        Text(
                            date,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 8.dp),
                        )
                    }
                    items(txs, key = { it.id }) { tx ->
                        TransactionRow(
                            tx = tx,
                            onClick = { selectedTx = tx },
                        )
                    }
                }
            }
        }
    }

    // Advanced filter sheet
    if (showFilterSheet) {
        AdvancedFilterSheet(
            searchText = searchText,
            onSearchTextChange = { searchText = it },
            amountMin = amountMin,
            onAmountMinChange = { amountMin = it },
            amountMax = amountMax,
            onAmountMaxChange = { amountMax = it },
            filterCategories = filterCategories,
            onFilterCategoriesChange = { filterCategories = it },
            onReset = { searchText = ""; amountMin = 0f; amountMax = 1000f; filterCategories = emptySet() },
            onDismiss = { showFilterSheet = false },
        )
    }

    // Category editor bottom sheet
    selectedTx?.let { tx ->
        CategoryEditorSheet(
            transaction = tx,
            onDismiss = {
                selectedTx = null
                reload()
            },
        )
    }
}

@Composable
private fun TransactionRow(tx: Transaction, onClick: () -> Unit) {
    val category = WimgCategory.fromId(tx.category)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .wimgCard(WimgShapes.small)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Category icon
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(category.color.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                category.icon,
                contentDescription = null,
                tint = category.color,
                modifier = Modifier.size(18.dp),
            )
        }

        Spacer(Modifier.width(12.dp))

        // Description
        Column(modifier = Modifier.weight(1f)) {
            Text(
                tx.description,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
            )
            Text(
                category.label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // Amount
        Text(
            formatAmountShort(tx.amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = if (tx.isIncome) WimgCategory.INCOME.color else MaterialTheme.colorScheme.onSurface,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CategoryEditorSheet(transaction: Transaction, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    val categories = listOf(
        WimgCategory.GROCERIES, WimgCategory.DINING, WimgCategory.TRANSPORT,
        WimgCategory.HOUSING, WimgCategory.UTILITIES, WimgCategory.ENTERTAINMENT,
        WimgCategory.SHOPPING, WimgCategory.HEALTH, WimgCategory.INSURANCE,
        WimgCategory.SUBSCRIPTIONS, WimgCategory.TRAVEL, WimgCategory.EDUCATION,
        WimgCategory.CASH, WimgCategory.TRANSFER, WimgCategory.OTHER,
    )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxHeight(0.85f)
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            Text(
                transaction.description,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(bottom = 4.dp),
            )
            Text(
                formatAmountShort(transaction.amount),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Black,
                color = if (transaction.isIncome) WimgCategory.INCOME.color else MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(16.dp))

            if (transaction.isIncome) {
                CategoryOption(WimgCategory.INCOME, transaction.category == WimgCategory.INCOME.id) {
                    LibWimg.setCategory(transaction.id, WimgCategory.INCOME.id)
                    onDismiss()
                }
            }
            categories.forEach { cat ->
                CategoryOption(cat, transaction.category == cat.id) {
                    LibWimg.setCategory(transaction.id, cat.id)
                    onDismiss()
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
internal fun CategoryOption(category: WimgCategory, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(category.color.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                category.icon,
                contentDescription = null,
                tint = category.color,
                modifier = Modifier.size(16.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            category.label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        if (selected) {
            Text("✓", fontWeight = FontWeight.Bold)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AdvancedFilterSheet(
    searchText: String,
    onSearchTextChange: (String) -> Unit,
    amountMin: Float,
    onAmountMinChange: (Float) -> Unit,
    amountMax: Float,
    onAmountMaxChange: (Float) -> Unit,
    filterCategories: Set<Int>,
    onFilterCategoriesChange: (Set<Int>) -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
) {
    val allCategories = listOf(
        WimgCategory.GROCERIES, WimgCategory.DINING, WimgCategory.TRANSPORT,
        WimgCategory.HOUSING, WimgCategory.UTILITIES, WimgCategory.ENTERTAINMENT,
        WimgCategory.SHOPPING, WimgCategory.HEALTH, WimgCategory.INSURANCE,
        WimgCategory.SUBSCRIPTIONS, WimgCategory.TRAVEL, WimgCategory.EDUCATION,
        WimgCategory.CASH, WimgCategory.TRANSFER, WimgCategory.INCOME, WimgCategory.OTHER,
    )

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // Search
            OutlinedTextField(
                value = searchText, onValueChange = onSearchTextChange,
                placeholder = { Text("Suchen nach...") },
                leadingIcon = { Icon(Icons.Outlined.Search, null) },
                singleLine = true, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp),
            )

            // Amount
            Column {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TText("Betrag", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    Text("${amountMin.toInt()} – ${if (amountMax >= 1000) "∞" else amountMax.toInt().toString()} €", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("Min", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Slider(value = amountMin, onValueChange = onAmountMinChange, valueRange = 0f..500f, steps = 9, colors = SliderDefaults.colors(thumbColor = WimgColors.accent, activeTrackColor = WimgColors.accent))
                Text("Max", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Slider(value = amountMax, onValueChange = onAmountMaxChange, valueRange = 50f..1000f, steps = 18, colors = SliderDefaults.colors(thumbColor = WimgColors.accent, activeTrackColor = WimgColors.accent))
            }

            // Categories grid
            Column {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TText("Kategorien", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    if (filterCategories.isNotEmpty()) {
                        TextButton(onClick = { onFilterCategoriesChange(emptySet()) }) { Text("Zurücksetzen", style = MaterialTheme.typography.labelSmall) }
                    }
                }
                Spacer(Modifier.height(8.dp))
                allCategories.chunked(4).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { cat ->
                            val active = filterCategories.contains(cat.id)
                            Column(
                                modifier = Modifier.weight(1f).clickable { onFilterCategoriesChange(if (active) filterCategories - cat.id else filterCategories + cat.id) }.padding(vertical = 6.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Box(
                                    modifier = Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(cat.color.copy(alpha = if (active) 0.25f else 0.08f)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(cat.icon, null, tint = cat.color, modifier = Modifier.size(18.dp))
                                }
                                Text(cat.label, style = MaterialTheme.typography.labelSmall, fontWeight = if (active) FontWeight.Bold else FontWeight.Normal, maxLines = 1, fontSize = 10.sp)
                            }
                        }
                        repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }

            // Actions
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (filterCategories.isNotEmpty() || searchText.isNotBlank() || amountMin > 0 || amountMax < 1000) {
                    OutlinedButton(onClick = onReset, modifier = Modifier.weight(1f), shape = WimgShapes.small) { Text("Zurücksetzen") }
                }
                Button(onClick = onDismiss, modifier = Modifier.weight(1f), shape = WimgShapes.small, colors = ButtonDefaults.buttonColors(containerColor = WimgColors.accent, contentColor = WimgColors.heroText)) {
                    Text("Ergebnisse anzeigen", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
