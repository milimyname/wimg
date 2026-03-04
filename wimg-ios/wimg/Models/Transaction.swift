import Foundation

struct Transaction: Codable, Identifiable {
    let id: String
    let date: String
    let description: String
    let amount: Double
    let currency: String
    let category: Int

    var isExpense: Bool { amount < 0 }
    var isIncome: Bool { amount > 0 }
    var absAmount: Double { abs(amount) }

    var dateFormatted: String {
        // date comes as "YYYY-MM-DD"
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}

struct ImportResult: Codable {
    let total_rows: Int
    let imported: Int
    let skipped_duplicates: Int
    let errors: Int
    let format: String
    let categorized: Int
}
