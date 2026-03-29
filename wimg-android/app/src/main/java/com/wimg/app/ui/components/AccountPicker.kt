package com.wimg.app.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.Account

@Composable
fun AccountPicker(
    selectedAccount: String?,
    onAccountChanged: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val accounts = remember { LibWimg.getAccounts() }

    if (accounts.size <= 1) return

    Box(modifier = modifier) {
        TextButton(onClick = { expanded = true }) {
            Icon(Icons.Outlined.AccountBalance, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(
                accounts.find { it.id == selectedAccount }?.name ?: "Alle Konten",
                style = MaterialTheme.typography.labelMedium,
            )
        }

        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("Alle Konten") },
                onClick = { onAccountChanged(null); expanded = false },
            )
            accounts.forEach { account ->
                DropdownMenuItem(
                    text = { Text(account.name) },
                    onClick = { onAccountChanged(account.id); expanded = false },
                )
            }
        }
    }
}
