import Foundation

struct RecurringPattern: Codable, Identifiable {
    let id: String
    let merchant: String
    let amount: Double
    let interval: String
    let category: Int
    let last_seen: String
    let next_due: String?
    let active: Int
    let prev_amount: Double?
    let price_change: Double?

    var isActive: Bool { active != 0 }
    var hasPriceChange: Bool { price_change != nil && abs(price_change!) > 0 }
    var isPriceUp: Bool { (price_change ?? 0) > 0 }

    var intervalLabel: String {
        switch interval {
        case "weekly": String(localized: "Wöchentlich")
        case "monthly": String(localized: "Monatlich")
        case "quarterly": String(localized: "Vierteljährlich")
        case "annual": String(localized: "Jährlich")
        default: interval
        }
    }

    private static var isEnglish: Bool {
        UserDefaults.standard.string(forKey: "wimg_locale") == "en"
    }

    private static var displayLocale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "de_DE")
    }

    var nextDueFormatted: String? {
        guard let next_due else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: next_due) else { return nil }

        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0

        if days < 0 { return String(localized: "\(abs(days))T überfällig") }
        if days == 0 { return String(localized: "Heute") }
        if days == 1 { return String(localized: "Morgen") }
        if days <= 7 { return String(localized: "In \(days) Tagen") }

        let display = DateFormatter()
        display.dateFormat = Self.isEnglish ? "MMM d" : "d. MMM"
        display.locale = Self.displayLocale
        return display.string(from: date)
    }

    var lastSeenFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: last_seen) else { return last_seen }
        let display = DateFormatter()
        display.dateFormat = Self.isEnglish ? "MMM d" : "d. MMM"
        display.locale = Self.displayLocale
        return display.string(from: date)
    }
}
