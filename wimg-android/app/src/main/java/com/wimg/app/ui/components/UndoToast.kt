package com.wimg.app.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.wimg.app.bridge.LibWimg
import kotlinx.coroutines.delay

/**
 * Manages undo toast state. Use as a shared instance across screens.
 */
class UndoState {
    var message by mutableStateOf<String?>(null)
        private set

    fun show(msg: String) {
        message = msg
    }

    fun dismiss() {
        message = null
    }

    fun undo() {
        LibWimg.undo()
        message = null
    }
}

@Composable
fun rememberUndoState(): UndoState {
    return remember { UndoState() }
}

@Composable
fun UndoSnackbarHost(undoState: UndoState) {
    val msg = undoState.message ?: return

    LaunchedEffect(msg) {
        delay(4000)
        undoState.dismiss()
    }

    Snackbar(
        modifier = Modifier.padding(16.dp),
        shape = RoundedCornerShape(16.dp),
        action = {
            TextButton(onClick = { undoState.undo() }) {
                Text("Rückgängig", color = MaterialTheme.colorScheme.primary)
            }
        },
        dismissAction = {
            TextButton(onClick = { undoState.dismiss() }) {
                Text("✕", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
    ) {
        Text(msg)
    }
}
