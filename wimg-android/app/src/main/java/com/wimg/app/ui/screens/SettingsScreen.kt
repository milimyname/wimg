package com.wimg.app.ui.screens

import android.content.Intent
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.wimg.app.bridge.LibWimg
import com.wimg.app.ui.theme.WimgShapes
import java.io.File

private enum class ThemeMode(val label: String, val nightMode: Int) {
    SYSTEM("System", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM),
    LIGHT("Hell", AppCompatDelegate.MODE_NIGHT_NO),
    DARK("Dunkel", AppCompatDelegate.MODE_NIGHT_YES),
}

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("wimg", 0)
    var theme by remember { mutableStateOf(ThemeMode.entries.find { it.nightMode == prefs.getInt("wimg_theme", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM) } ?: ThemeMode.SYSTEM) }
    var locale by remember { mutableStateOf(prefs.getString("wimg_locale", "de") ?: "de") }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Appearance
        item {
            Text("Darstellung", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Design", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    ThemeMode.entries.forEach { mode ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(
                                selected = theme == mode,
                                onClick = {
                                    theme = mode
                                    prefs.edit().putInt("wimg_theme", mode.nightMode).apply()
                                    AppCompatDelegate.setDefaultNightMode(mode.nightMode)
                                },
                            )
                            Text(mode.label, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Sprache", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    listOf("de" to "Deutsch", "en" to "English").forEach { (code, label) ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(
                                selected = locale == code,
                                onClick = {
                                    locale = code
                                    prefs.edit().putString("wimg_locale", code).apply()
                                },
                            )
                            Text(label, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }

        // Data section
        item {
            Spacer(Modifier.height(8.dp))
            Text("Daten", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column {
                    SettingsRow(icon = Icons.Outlined.FileUpload, title = "CSV exportieren") {
                        val csv = com.wimg.app.bridge.WimgJni.nativeExportCsv() ?: return@SettingsRow
                        shareText(context, csv, "wimg-export.csv")
                    }
                    HorizontalDivider(modifier = Modifier.padding(start = 56.dp))
                    SettingsRow(icon = Icons.Outlined.Storage, title = "Datenbank exportieren") {
                        val json = com.wimg.app.bridge.WimgJni.nativeExportDb() ?: return@SettingsRow
                        shareText(context, json, "wimg-backup.json")
                    }
                }
            }
        }

        // Danger zone
        item {
            Spacer(Modifier.height(8.dp))
            Text("Danger Zone", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error)
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                SettingsRow(icon = Icons.Outlined.DeleteForever, title = "Alle Daten löschen", isDestructive = true) {
                    val dbFile = File(context.filesDir, "wimg.db")
                    LibWimg.close()
                    dbFile.delete()
                    LibWimg.initialize(context)
                }
            }
        }
    }
}

@Composable
private fun SettingsRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    isDestructive: Boolean = false,
    onClick: () -> Unit,
) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = WimgShapes.small,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                icon, contentDescription = null,
                tint = if (isDestructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(16.dp))
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = if (isDestructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

private fun shareText(context: android.content.Context, content: String, filename: String) {
    val file = File(context.cacheDir, filename)
    file.writeText(content)
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/*"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Exportieren"))
}
