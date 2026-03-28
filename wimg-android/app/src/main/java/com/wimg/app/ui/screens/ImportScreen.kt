package com.wimg.app.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.ImportResult
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes

@Composable
fun ImportScreen(navController: NavController) {
    val context = LocalContext.current
    var importing by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<ImportResult?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    val filePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        importing = true
        error = null
        try {
            val bytes = context.contentResolver.openInputStream(uri)?.readBytes()
                ?: throw Exception("Could not read file")
            result = LibWimg.importCsv(bytes)
        } catch (e: Exception) {
            error = e.message ?: "Import fehlgeschlagen"
        }
        importing = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(32.dp))

        if (result != null) {
            // Result card
            val r = result!!
            Card(
                shape = WimgShapes.large,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        modifier = Modifier
                            .size(64.dp)
                            .clip(CircleShape)
                            .background(WimgCategory.INCOME.color.copy(alpha = 0.1f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("✓", fontSize = MaterialTheme.typography.headlineMedium.fontSize, color = WimgCategory.INCOME.color)
                    }
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "Import erfolgreich!",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(12.dp))
                    ResultRow("Format", r.format)
                    ResultRow("Importiert", "${r.imported}")
                    if (r.skipped_duplicates > 0) ResultRow("Duplikate", "${r.skipped_duplicates}")
                    if (r.categorized > 0) ResultRow("Kategorisiert", "${r.categorized}")
                }
            }

            Spacer(Modifier.height(16.dp))

            Button(
                onClick = {
                    navController.navigate("dashboard") {
                        popUpTo("dashboard") { inclusive = true }
                    }
                },
                shape = WimgShapes.small,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.onBackground,
                    contentColor = MaterialTheme.colorScheme.background,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Zum Dashboard", modifier = Modifier.padding(vertical = 8.dp), fontWeight = FontWeight.Bold)
            }

            OutlinedButton(
                onClick = {
                    navController.navigate("transactions") {
                        popUpTo("dashboard")
                    }
                },
                shape = WimgShapes.small,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Transaktionen ansehen", modifier = Modifier.padding(vertical = 8.dp))
            }
        } else {
            // Upload card
            Card(
                shape = WimgShapes.large,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(28.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        modifier = Modifier
                            .size(80.dp)
                            .clip(CircleShape)
                            .background(WimgColors.accent.copy(alpha = 0.2f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Outlined.FileUpload,
                            contentDescription = null,
                            modifier = Modifier.size(36.dp),
                            tint = WimgColors.heroText,
                        )
                    }
                    Spacer(Modifier.height(20.dp))
                    Text(
                        "CSV-Datei importieren",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Comdirect, Trade Republic oder Scalable Capital",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(Modifier.height(24.dp))

            Button(
                onClick = { filePicker.launch("text/*") },
                enabled = !importing,
                shape = WimgShapes.small,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.onBackground,
                    contentColor = MaterialTheme.colorScheme.background,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (importing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.background,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("Importiere...", fontWeight = FontWeight.Bold)
                } else {
                    Text("Datei auswählen", modifier = Modifier.padding(vertical = 8.dp), fontWeight = FontWeight.Bold)
                }
            }

            if (error != null) {
                Spacer(Modifier.height(12.dp))
                Card(
                    shape = WimgShapes.small,
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                ) {
                    Text(
                        error!!,
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun ResultRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Bold,
        )
    }
}

// Re-use from models
private typealias WimgCategory = com.wimg.app.models.WimgCategory
