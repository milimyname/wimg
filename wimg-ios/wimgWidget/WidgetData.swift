import Foundation

struct WidgetData {
    let available: Double
    let income: Double
    let expenses: Double
    let savingsRate: Int
    let nextMerchant: String?
    let nextAmount: Double?
    let nextDate: String?
    let recentTransactions: [(desc: String, amount: Double, date: String)]
    let updatedAt: Date
    /// User opted to hide € amounts in widgets. Stored in App Group defaults
    /// at `wimg_widget_mask_amounts` and read both here and by the views.
    let maskAmounts: Bool

    static let empty = WidgetData(
        available: 0, income: 0, expenses: 0, savingsRate: 0,
        nextMerchant: nil, nextAmount: nil, nextDate: nil,
        recentTransactions: [],
        updatedAt: .distantPast,
        maskAmounts: false
    )

    static func load() -> WidgetData {
        let defaults = UserDefaults(suiteName: "group.com.wimg.app")
        let mask = defaults?.bool(forKey: "wimg_widget_mask_amounts") ?? false
        guard let defaults,
              let jsonString = defaults.string(forKey: "wimg_widget_data"),
              let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return WidgetData(
            available: 0, income: 0, expenses: 0, savingsRate: 0,
            nextMerchant: nil, nextAmount: nil, nextDate: nil,
            recentTransactions: [], updatedAt: .distantPast,
            maskAmounts: mask
        ) }

        return WidgetData(
            available: dict["available"] as? Double ?? 0,
            income: dict["income"] as? Double ?? 0,
            expenses: dict["expenses"] as? Double ?? 0,
            savingsRate: dict["savings_rate"] as? Int ?? 0,
            nextMerchant: dict["next_recurring_merchant"] as? String,
            nextAmount: dict["next_recurring_amount"] as? Double,
            nextDate: dict["next_recurring_date"] as? String,
            recentTransactions: {
                guard let txArray = dict["recent_transactions"] as? [[String: Any]] else { return [] }
                return txArray.prefix(5).map { tx in
                    (desc: tx["description"] as? String ?? "",
                     amount: tx["amount"] as? Double ?? 0,
                     date: tx["date"] as? String ?? "")
                }
            }(),
            updatedAt: Date(timeIntervalSince1970: dict["updated_at"] as? Double ?? 0),
            maskAmounts: mask
        )
    }

    var hasData: Bool { updatedAt != .distantPast }

    var nextDateFormatted: String? {
        guard let nextDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: nextDate) else { return nil }
        let lang = UserDefaults(suiteName: "group.com.wimg.app")?.string(forKey: "wimg_locale")
            ?? UserDefaults.standard.string(forKey: "wimg_locale")
            ?? "de"
        let display = DateFormatter()
        display.dateFormat = "d. MMM"
        display.locale = Locale(identifier: lang == "en" ? "en_US" : "de_DE")
        return display.string(from: date)
    }
}
