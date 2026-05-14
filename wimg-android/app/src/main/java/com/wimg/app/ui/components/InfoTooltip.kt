package com.wimg.app.ui.components

import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * Tiny "i" icon that pops a one-sentence explanation when tapped.
 * Replaces the dedicated About FAQ for first-encounter inline help.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InfoTooltip(text: String) {
    val state = rememberTooltipState(isPersistent = true)
    val scope = rememberCoroutineScope()

    TooltipBox(
        positionProvider = TooltipDefaults.rememberPlainTooltipPositionProvider(),
        tooltip = {
            PlainTooltip(modifier = Modifier.widthIn(max = 260.dp)) {
                Text(text)
            }
        },
        state = state,
    ) {
        IconButton(
            onClick = {
                scope.launch {
                    if (state.isVisible) state.dismiss() else state.show()
                }
            },
            modifier = Modifier.size(20.dp),
        ) {
            Icon(
                Icons.Outlined.Info,
                contentDescription = "Mehr Infos",
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                modifier = Modifier.size(14.dp),
            )
        }
    }
}
