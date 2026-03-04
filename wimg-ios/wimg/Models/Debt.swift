import Foundation

struct Debt: Codable, Identifiable {
    let id: String
    let name: String
    let total: Double
    let paid: Double
    let monthly: Double

    var remaining: Double { total - paid }
    var progress: Double { total > 0 ? paid / total : 0 }
    var isPaidOff: Bool { paid >= total }
}
