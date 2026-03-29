package com.wimg.app.ui.components

import android.content.Context
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

private const val PREFS = "wimg_coachmarks"

object CoachmarkManager {
    fun isDismissed(context: Context, key: String): Boolean {
        return context.getSharedPreferences(PREFS, 0).getBoolean(key, false)
    }

    fun dismiss(context: Context, key: String) {
        context.getSharedPreferences(PREFS, 0).edit().putBoolean(key, true).apply()
    }
}

@Composable
fun Coachmark(
    key: String,
    text: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var visible by remember { mutableStateOf(!CoachmarkManager.isDismissed(context, key)) }

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn() + slideInVertically(),
        exit = fadeOut() + slideOutVertically(),
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier
                .shadow(8.dp, RoundedCornerShape(12.dp))
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.onBackground)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.background,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = {
                CoachmarkManager.dismiss(context, key)
                visible = false
            }) {
                Text(
                    "OK",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.background,
                )
            }
        }
    }
}
