import Foundation

struct MonthlySummary: Codable {
    let year: Int
    let month: Int
    let income: Double
    let expenses: Double
    let available: Double
    let tx_count: Int
    let by_category: [CategoryBreakdown]
}

struct CategoryBreakdown: Codable, Identifiable {
    let id: Int
    let name: String
    let amount: Double
    let count: Int
}
