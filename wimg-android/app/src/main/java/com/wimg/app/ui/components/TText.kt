package com.wimg.app.ui.components

import android.content.Context
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight

/**
 * Translated Text — looks up English translation at runtime based on
 * wimg_locale SharedPreferences. German is the source/default.
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
    val context = LocalContext.current
    val translated = translateIfNeeded(context, text)
    Text(
        text = translated,
        modifier = modifier,
        style = style,
        fontWeight = fontWeight,
        color = color,
        maxLines = maxLines,
    )
}

private fun translateIfNeeded(context: Context, text: String): String {
    val locale = context.getSharedPreferences("wimg", 0).getString("wimg_locale", "de") ?: "de"
    if (locale == "de") return text
    return TranslationMap.get(text) ?: text
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
        "Schulden" to "Debts",
        "Sparziele" to "Savings Goals",
        "Wiederkehrend" to "Recurring",
        "Steuern" to "Tax",
        "Rückblick" to "Review",
        "Bankverbindung" to "Bank Connection",
        "Import" to "Import",
        "Einstellungen" to "Settings",
        "Über wimg" to "About wimg",
        "Feedback" to "Feedback",

        // Debts
        "Keine Schulden" to "No Debts",
        "Verbleibend" to "Remaining",
        "Schuld hinzufügen" to "Add Debt",
        "Hinzufügen" to "Add",
        "Zahlen" to "Pay",
        "Löschen" to "Delete",
        "Gesamtbetrag (€)" to "Total Amount (€)",
        "Monatliche Rate (€)" to "Monthly Rate (€)",

        // Goals
        "Keine Sparziele" to "No Savings Goals",
        "Sparziel erstellen" to "Create Savings Goal",
        "Erstellen" to "Create",
        "Einzahlen" to "Deposit",
        "Zielbetrag (€)" to "Target Amount (€)",

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

        // Tax
        "Gesamtabzug" to "Total Deduction",
        "Pendler" to "Commuter",
        "Homeoffice" to "Home Office",
        "Gesamt" to "Total",
        "Pendlerpauschale" to "Commuter Allowance",
        "Homeoffice-Pauschale" to "Home Office Allowance",
        "Entfernung (km, einfach)" to "Distance (km, one way)",
        "Arbeitstage pro Jahr" to "Work Days per Year",
        "Homeoffice-Tage (max. 210)" to "Home Office Days (max. 210)",

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

        // Feedback
        "Feedback senden" to "Send Feedback",
        "Feedback gesendet!" to "Feedback Sent!",
        "Nachricht" to "Message",
        "Sende..." to "Sending...",

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
        "Sparziele & Vermögen" to "Savings Goals & Net Worth",
        "Setze Sparziele, verfolge deinen Fortschritt und sieh dein Nettovermögen über die Zeit." to "Set savings goals, track your progress, and see your net worth over time.",
        "Steuern & Sync" to "Tax & Sync",
        "Finde absetzbare Ausgaben für deine Steuererklärung. Synchronisiere optional zwischen Geräten." to "Find deductible expenses for your tax return. Optionally sync between devices.",
        "Weiter" to "Next",
        "Los geht's" to "Let's go",

        // Undo
        "Rückgängig" to "Undo",
    )

    fun get(key: String): String? = map[key]
}
