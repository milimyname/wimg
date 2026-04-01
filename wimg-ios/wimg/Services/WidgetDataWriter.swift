import Foundation
import WidgetKit

enum WidgetDataWriter {
    private static let suiteName = "group.com.wimg.app"
    private static let key = "wimg_widget_data"

    static func writeSummary() {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)

        let summary = LibWimg.getSummary(year: year, month: month)
        let income = summary.income
        let expenses = summary.expenses
        let savingsRate = income > 0 ? Int(((income - expenses) / income) * 100) : 0

        var data: [String: Any] = [
            "available": summary.available,
            "income": income,
            "expenses": expenses,
            "savings_rate": savingsRate,
            "updated_at": Int(now.timeIntervalSince1970),
        ]

        // Recent transactions for large widget
        let transactions = (try? LibWimg.getTransactions()) ?? []
        let recentTx = transactions.sorted { $0.date > $1.date }.prefix(5).map { tx -> [String: Any] in
            ["description": tx.description, "amount": tx.amount, "date": tx.date]
        }
        data["recent_transactions"] = Array(recentTx)

        let recurring = LibWimg.getRecurring()
            .filter { $0.isActive && $0.next_due != nil }
            .sorted { ($0.next_due ?? "") < ($1.next_due ?? "") }
        if let next = recurring.first {
            data["next_recurring_merchant"] = next.merchant
            data["next_recurring_amount"] = next.amount
            data["next_recurring_date"] = next.next_due
        }

        guard let defaults = UserDefaults(suiteName: suiteName),
              let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        defaults.set(jsonString, forKey: key)

        WidgetCenter.shared.reloadAllTimelines()
    }
}
