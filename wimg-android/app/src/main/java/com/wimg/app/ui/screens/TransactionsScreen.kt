package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.formatAmountShort
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

    fun reload() {
        transactions = LibWimg.getTransactionsFiltered(selectedAccount).sortedByDescending { it.date }
    }

    LaunchedEffect(selectedAccount) { reload() }

    val filtered = transactions.filter { tx ->
        when (filter) {
            TxFilter.ALL -> !tx.isExcluded
            TxFilter.EXPENSES -> tx.isExpense && !tx.isExcluded
            TxFilter.INCOME -> tx.isIncome && !tx.isExcluded
        }
    }

    val grouped = filtered.groupBy { it.date }.toSortedMap(compareByDescending { it })

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        // Segmented filter
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
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
    val sheetState = rememberModalBottomSheetState()

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
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
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
