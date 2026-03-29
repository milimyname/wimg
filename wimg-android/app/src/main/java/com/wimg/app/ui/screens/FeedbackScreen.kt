package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

private val TYPES = listOf(
    Triple("bug", "🐛", "Bug"),
    Triple("feature", "✨", "Feature"),
    Triple("feedback", "💬", "Feedback"),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedbackScreen() {
    var type by remember { mutableStateOf("feedback") }
    var message by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var success by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp),
    ) {
        if (success) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("✅", fontSize = 48.sp)
                    Spacer(Modifier.height(12.dp))
                    Text("Feedback gesendet!", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("Danke für dein Feedback.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(24.dp))
                    OutlinedButton(onClick = { success = false; message = "" }) {
                        Text("Weiteres Feedback")
                    }
                }
            }
        } else {
            Text("Feedback", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))

            // Type selector
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TYPES.forEach { (id, emoji, label) ->
                    FilterChip(
                        selected = type == id,
                        onClick = { type = id },
                        label = { Text("$emoji $label") },
                    )
                }
            }

            Spacer(Modifier.height(16.dp))

            OutlinedTextField(
                value = message,
                onValueChange = { message = it },
                label = { Text("Nachricht") },
                modifier = Modifier.fillMaxWidth().height(160.dp),
                maxLines = 8,
            )

            Spacer(Modifier.height(16.dp))

            Button(
                onClick = {
                    sending = true; error = null
                    scope.launch {
                        try {
                            withContext(Dispatchers.IO) {
                                val body = """{"type":"$type","message":"${message.replace("\"", "\\\"")}","platform":"android"}"""
                                val request = Request.Builder()
                                    .url("https://wimg-sync.mili-my.name/feedback")
                                    .post(body.toRequestBody("application/json".toMediaType()))
                                    .build()
                                OkHttpClient().newCall(request).execute().close()
                            }
                            success = true
                        } catch (e: Exception) {
                            error = e.message ?: "Senden fehlgeschlagen"
                        }
                        sending = false
                    }
                },
                enabled = !sending && message.trim().length >= 3,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.onBackground,
                    contentColor = MaterialTheme.colorScheme.background,
                ),
            ) {
                Text(if (sending) "Sende..." else "Feedback senden", fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }

            if (error != null) {
                Spacer(Modifier.height(8.dp))
                Card(shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Text(error!!, modifier = Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
