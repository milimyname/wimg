import Foundation

struct Snapshot: Codable, Identifiable {
    let id: String
    let date: String
    let net_worth: Double
    let income: Double
    let expenses: Double
    let tx_count: Int
    let by_category: [SnapshotCategory]

    struct SnapshotCategory: Codable {
        let id: Int
        let amount: Double
    }
}
