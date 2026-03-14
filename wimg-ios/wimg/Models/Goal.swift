import Foundation

struct Goal: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let target: Double
    let current: Double
    let deadline: String?

    var remaining: Double { target - current }
    var progress: Double { target > 0 ? current / target : 0 }
    var isComplete: Bool { current >= target }

    var deadlineDate: Date? {
        guard let deadline else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: deadline)
    }
}
