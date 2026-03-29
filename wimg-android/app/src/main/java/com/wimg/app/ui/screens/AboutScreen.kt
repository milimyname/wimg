package com.wimg.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard

private data class FAQ(val q: String, val a: String)

private val faqs = listOf(
    FAQ("Sind meine Daten sicher?", "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext."),
    FAQ("Welche Banken werden unterstützt?", "CSV-Import von Comdirect, Trade Republic und Scalable Capital. Da wimg Open-Source ist, können weitere Formate jederzeit hinzugefügt werden."),
    FAQ("Wie funktioniert der Import?", "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln."),
    FAQ("Wie funktioniert die Kategorisierung?", "wimg nutzt ein Regel-System mit Schlüsselwörtern. Bekannte Händler (REWE, LIDL, etc.) werden automatisch erkannt. Wenn du eine Transaktion manuell kategorisierst, lernt wimg das Muster und wendet es zukünftig automatisch an."),
    FAQ("Ist wimg wirklich kostenlos?", "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten."),
    FAQ("Wo werden die Daten gespeichert?", "Auf Android: lokale SQLite-Datei. Deine Daten verlassen dein Gerät nur bei aktivierter Sync — dann Ende-zu-Ende verschlüsselt."),
    FAQ("Was ist der MCP-Server?", "Mit aktivierter Synchronisierung wird dein Sync-Schlüssel zum MCP-Zugang. Claude.ai oder andere KI-Tools können Ausgaben abfragen, Kategorien setzen und Schulden verwalten — Ende-zu-Ende verschlüsselt."),
    FAQ("Wie funktioniert Auto-Learn?", "Wenn du eine Transaktion manuell kategorisierst, lernt wimg automatisch das Schlüsselwort. Beim nächsten Import oder Auto-Kategorisieren werden ähnliche Transaktionen automatisch zugeordnet."),
    FAQ("Was zeigt das Vermögens-Diagramm?", "Das Vermögens-Diagramm auf der Analyse-Seite zeigt dein kumulatives Nettovermögen über die Zeit — basierend auf monatlichen Snapshots. Du brauchst mindestens 2 Snapshots."),
    FAQ("Wie synchronisiere ich zwischen Geräten?", "Gehe zu Einstellungen → Sync aktivieren. Kopiere den Sync-Schlüssel und füge ihn auf dem zweiten Gerät ein. Änderungen werden in Echtzeit per WebSocket synchronisiert."),
    FAQ("Wie funktionieren Sparziele?", "Unter Mehr → Sparziele kannst du Sparziele mit Name, Icon, Zielbetrag und optionaler Deadline erstellen. Über den Einzahlen-Button trägst du Beträge ein."),
    FAQ("Wie erkennt wimg Abos?", "wimg analysiert deine Transaktionen automatisch und erkennt regelmäßige Muster (monatlich, vierteljährlich, jährlich). Unter Mehr → Wiederkehrend siehst du alle erkannten Abos."),
    FAQ("Funktioniert wimg offline?", "Ja, vollständig. Alle Daten liegen lokal in SQLite. Du brauchst kein Internet für Import, Kategorisierung, Analyse oder irgendeine Kernfunktion."),
    FAQ("Kann ich mehrere Konten verwalten?", "Ja. Neue Konten werden beim CSV-Import automatisch erstellt oder können manuell angelegt werden."),
    FAQ("Kann ich Änderungen rückgängig machen?", "Ja. wimg speichert bis zu 50 Undo-Schritte. Über die Suche findest du Rückgängig und Wiederherstellen."),
    FAQ("Was kann die Steuern-Seite?", "Sie berechnet Pendlerpauschale und Homeoffice-Pauschale und scannt Transaktionen nach steuerrelevanten Schlüsselwörtern."),
    FAQ("Wie lösche ich meine Daten?", "Unter Einstellungen → Danger Zone kannst du die Datenbank zurücksetzen. Diese Aktion kann nicht rückgängig gemacht werden."),
    FAQ("Was ist die Sparquote?", "Die Sparquote zeigt, welchen Anteil deines Einkommens du sparst: (Einnahmen − Ausgaben) ÷ Einnahmen × 100."),
    FAQ("Wie kann ich beitragen?", "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen."),
)

@Composable
fun AboutScreen() {
    val context = LocalContext.current
    val version = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "—"
    } catch (_: Exception) { "—" }
    var expandedFaq by remember { mutableStateOf<String?>(null) }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Hero
        item {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
            ) {
                Box {
                    Box(
                        modifier = Modifier.size(80.dp).clip(CircleShape).background(WimgColors.heroText),
                        contentAlignment = Alignment.Center,
                    ) { Text("💰", fontSize = 32.sp) }
                    Box(
                        modifier = Modifier.size(28.dp).clip(CircleShape).background(WimgCategory.INCOME.color).align(Alignment.BottomEnd),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Outlined.CheckCircle, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
                }
                Spacer(Modifier.height(12.dp))
                Text("wimg", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("v$version", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Text("Persönliche Finanzverwaltung.\nLokal. Privat. Offen.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
        }

        // Privacy
        item {
            Row(
                modifier = Modifier.fillMaxWidth().wimgCard().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(modifier = Modifier.size(44.dp).clip(CircleShape).background(WimgCategory.INCOME.color), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Lock, null, tint = Color.White)
                }
                Spacer(Modifier.width(16.dp))
                Column {
                    Text("Privatsphäre zuerst", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                    Text("Keine Werbung. Kein Tracking. Niemals.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        // Tech
        item {
            Row(
                modifier = Modifier.fillMaxWidth().wimgCard().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(modifier = Modifier.size(44.dp).clip(CircleShape).background(WimgColors.accent), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Code, null, tint = WimgColors.heroText)
                }
                Spacer(Modifier.width(16.dp))
                Column {
                    Text("Open Source", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                    Text("Zig + SQLite + Kotlin + Compose", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        // GitHub
        item {
            OutlinedButton(
                onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/milimyname/wimg"))) },
                modifier = Modifier.fillMaxWidth(),
                shape = WimgShapes.small,
            ) { Text("GitHub", fontWeight = FontWeight.Bold) }
        }

        // FAQ section
        item {
            Spacer(Modifier.height(8.dp))
            Text(
                "HÄUFIGE FRAGEN",
                style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.8.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 4.dp),
            )
        }

        items(faqs) { faq ->
            val isExpanded = expandedFaq == faq.q
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .wimgCard(WimgShapes.small)
                    .clickable { expandedFaq = if (isExpanded) null else faq.q }
                    .padding(16.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        faq.q,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        if (isExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                }
                AnimatedVisibility(visible = isExpanded) {
                    Text(
                        faq.a,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
            }
        }

        // Credits
        item {
            Text(
                "Ein Open-Source-Projekt von Komiljon Maksudov.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
            )
        }
    }
}
