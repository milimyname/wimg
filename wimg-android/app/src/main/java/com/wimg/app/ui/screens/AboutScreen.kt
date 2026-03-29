package com.wimg.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes

@Composable
fun AboutScreen() {
    val context = LocalContext.current
    val version = context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "—"

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Hero
        item {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(vertical = 16.dp)) {
                Box {
                    Box(
                        modifier = Modifier.size(80.dp).clip(CircleShape).background(WimgColors.heroText),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("💰", fontSize = 32.sp)
                    }
                    Box(
                        modifier = Modifier.size(28.dp).clip(CircleShape).background(WimgCategory.INCOME.color).align(Alignment.BottomEnd),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(16.dp))
                    }
                }
                Spacer(Modifier.height(12.dp))
                Text("wimg", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("v$version", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Persönliche Finanzverwaltung.\nLokal. Privat. Offen.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }

        // Privacy
        item {
            Card(shape = WimgShapes.medium, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier.size(44.dp).clip(CircleShape).background(WimgCategory.INCOME.color),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Outlined.Lock, contentDescription = null, tint = androidx.compose.ui.graphics.Color.White)
                    }
                    Spacer(Modifier.width(16.dp))
                    Column {
                        Text("Privatsphäre zuerst", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                        Text("Keine Werbung. Kein Tracking. Niemals.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        // Tech
        item {
            Card(shape = WimgShapes.medium, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Outlined.Code, contentDescription = null, tint = WimgColors.heroText)
                    }
                    Spacer(Modifier.width(16.dp))
                    Column {
                        Text("Open Source", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                        Text("Zig + SQLite + Kotlin + Compose", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        // GitHub button
        item {
            OutlinedButton(
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/milimyname/wimg")))
                },
                modifier = Modifier.fillMaxWidth(),
                shape = WimgShapes.small,
            ) {
                Text("GitHub", fontWeight = FontWeight.Bold)
            }
        }

        // Credits
        item {
            Text(
                "Ein Open-Source-Projekt von Komiljon Maksudov.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            )
        }
    }
}
