package com.wimg.app.ui.components

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import com.wimg.app.ui.theme.LocaleState

/**
 * Translated Text — looks up English translation at runtime based on
 * LocaleState.locale (observable). German is the source/default.
 * Mirrors iOS TText component.
 */
@Composable
fun TText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = TextStyle.Default,
    fontWeight: FontWeight? = null,
    color: Color = Color.Unspecified,
    maxLines: Int = Int.MAX_VALUE,
) {
    val translated = if (LocaleState.locale == "en") TranslationMap.get(text) ?: text else text
    Text(
        text = translated,
        modifier = modifier,
        style = style,
        fontWeight = fontWeight,
        color = color,
        maxLines = maxLines,
    )
}

/**
 * Hardcoded translation map for commonly used UI strings.
 * Generated from en.ts — covers the most visible Android UI strings.
 */
object TranslationMap {
    private val map = mapOf(
        // Navigation
        "Suche" to "Search",
        "Home" to "Home",
        "Umsätze" to "Transactions",
        "Mehr" to "More",

        // Dashboard
        "VERFÜGBAR" to "AVAILABLE",
        "Verfügbares Einkommen" to "Available Income",
        "Sparquote" to "Savings Rate",
        "Einnahmen" to "Income",
        "Ausgaben" to "Expenses",
        "Kategorien" to "Categories",
        "Keine Daten" to "No Data",
        "Importiere eine CSV-Datei um loszulegen" to "Import a CSV file to get started",
        "Beispieldaten laden" to "Load Demo Data",
        "Lade..." to "Loading...",
        "Transaktionen" to "Transactions",
        "Neue Version verfügbar" to "New version available",
        "Update" to "Update",
        "Was ist neu?" to "What's new?",

        // Transactions
        "Alle" to "All",
        "Keine Umsätze" to "No Transactions",
        "Importiere eine CSV-Datei" to "Import a CSV file",
        "Gesamtsaldo" to "Total Balance",
        "Transaktion im Blickfeld" to "transaction in view",
        "Transaktionen im Blickfeld" to "transactions in view",

        // Search
        "Transaktionen suchen..." to "Search transactions...",
        "Ergebnisse" to "Results",
        "Keine Ergebnisse" to "No Results",
        "Suche starten" to "Start Searching",
        "NAVIGATION" to "NAVIGATION",
        "KATEGORISIERUNG" to "CATEGORIZATION",
        "DATEN" to "DATA",
        "BEARBEITEN" to "EDIT",

        // Analysis
        "Vermögen" to "Net Worth",
        "Aktuell" to "Current",
        "Seit Beginn" to "Since Start",
        "Ausgaben-Heatmap" to "Spending Heatmap",

        // More
        "Analyse" to "Analysis",
        "Wiederkehrend" to "Recurring",
        "Rückblick" to "Review",
        "Bankverbindung" to "Bank Connection",
        "Import" to "Import",
        "Einstellungen" to "Settings",
        "Über wimg" to "About wimg",
        "Hinzufügen" to "Add",
        "Löschen" to "Delete",

        // Recurring
        "Abonnements" to "Subscriptions",
        "Kalender" to "Calendar",
        "Monatliche Fixkosten" to "Monthly Fixed Costs",
        "Wöchentlich" to "Weekly",
        "Monatlich" to "Monthly",
        "Vierteljährlich" to "Quarterly",
        "Jährlich" to "Annual",
        "Keine Muster erkannt" to "No Patterns Detected",
        "Erkennen" to "Detect",
        "Erneut erkennen" to "Detect Again",
        "Nächste 30 Tage" to "Next 30 Days",

        // Review
        "Gespart" to "Saved",
        "Defizit" to "Deficit",
        "Top Kategorien" to "Top Categories",

        // Settings
        "Darstellung" to "Appearance",
        "Design" to "Design",
        "Sprache" to "Language",
        "Features" to "Features",
        "Daten" to "Data",
        "Danger Zone" to "Danger Zone",
        "Sync aktivieren" to "Enable Sync",
        "Jetzt synchronisieren" to "Sync Now",
        "Synchronisiere..." to "Syncing...",
        "Alle Daten löschen" to "Delete All Data",
        "Alle Daten löschen?" to "Delete All Data?",
        "Diese Aktion kann nicht rückgängig gemacht werden." to "This action cannot be undone.",
        "Abbrechen" to "Cancel",
        "CSV exportieren" to "Export CSV",
        "Datenbank exportieren" to "Export Database",
        "Synchronisierung" to "Sync",

        // About
        "HÄUFIGE FRAGEN" to "FAQ",
        "Privatsphäre zuerst" to "Privacy First",
        "Keine Werbung. Kein Tracking. Niemals." to "No ads. No tracking. Ever.",
        "Open Source" to "Open Source",

        // Import
        "CSV-Datei importieren" to "Import CSV File",
        "Datei auswählen" to "Choose File",
        "Importiere..." to "Importing...",
        "Import erfolgreich!" to "Import Successful!",
        "Zum Dashboard" to "Go to Dashboard",
        "Transaktionen ansehen" to "View Transactions",
        "Format" to "Format",
        "Importiert" to "Imported",
        "Duplikate" to "Duplicates",
        "Kategorisiert" to "Categorized",

        // FinTS
        "Bank verbinden" to "Connect Bank",
        "Anmeldung" to "Login",
        "Verbinden" to "Connect",
        "Verbinde..." to "Connecting...",
        "Andere Bank wählen" to "Choose Another Bank",
        "TAN-Eingabe" to "Enter TAN",
        "Freigabe in Banking-App" to "Approve in Banking App",
        "TAN senden" to "Send TAN",
        "Status prüfen" to "Check Status",
        "Kontoauszüge abrufen" to "Fetch Statements",
        "Letzte 90 Tage" to "Last 90 Days",
        "Abrufen" to "Fetch",
        "Abruf erfolgreich!" to "Fetch Successful!",
        "Weitere Bank verbinden" to "Connect Another Bank",

        // Onboarding
        "Deine Finanzen, auf deinem Gerät" to "Your finances, on your device",
        "Keine Cloud, kein Konto. Deine Daten bleiben auf deinem Gerät — lokal, privat, offline." to "No cloud, no account. Your data stays on your device — local, private, offline.",
        "Importiere deine Bankdaten" to "Import your bank data",
        "Lade eine CSV-Datei von Comdirect, Trade Republic oder Scalable Capital hoch." to "Upload a CSV file from Comdirect, Trade Republic, or Scalable Capital.",
        "Wiederkehrend erkennen" to "Detect Recurring Payments",
        "Erkenne Abos und Fixkosten automatisch. Sieh, was monatlich fällig wird." to "Automatically detect subscriptions and fixed costs. See what's due each month.",
        "Geräte synchronisieren" to "Sync Devices",
        "Synchronisiere optional zwischen Geräten — Ende-zu-Ende verschlüsselt." to "Optionally sync between devices — end-to-end encrypted.",
        "Weiter" to "Next",
        "Los geht's" to "Let's go",

        // Undo
        "Rückgängig" to "Undo",
    )

    fun get(key: String): String? = map[key]
}
