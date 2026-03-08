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
        case "weekly": "Wöchentlich"
        case "monthly": "Monatlich"
        case "quarterly": "Vierteljährlich"
        case "annual": "Jährlich"
        default: interval
        }
    }

    var nextDueFormatted: String? {
        guard let next_due else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: next_due) else { return nil }

        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0

        if days < 0 { return "\(abs(days))T überfällig" }
        if days == 0 { return "Heute" }
        if days == 1 { return "Morgen" }
        if days <= 7 { return "In \(days) Tagen" }

        let display = DateFormatter()
        display.dateFormat = "dd. MMM"
        display.locale = Locale(identifier: "de_DE")
        return display.string(from: date)
    }

    var lastSeenFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: last_seen) else { return last_seen }
        let display = DateFormatter()
        display.dateFormat = "dd. MMM"
        display.locale = Locale(identifier: "de_DE")
        return display.string(from: date)
    }
}
