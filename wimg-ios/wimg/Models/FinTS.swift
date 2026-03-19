import Foundation

// MARK: - FinTS Models (Phase 4A)

struct BankInfo: Codable, Identifiable {
    let blz: String
    let name: String
    let url: String

    var id: String { blz }
}

struct FintsStatusResult: Codable {
    let status: String       // "ok", "error", "tan_required"
    let challenge: String?   // TAN challenge text (when status == "tan_required")
    let phototan: String?    // Base64-encoded photoTAN PNG image
    let decoupled: Bool?     // true when bank expects decoupled/push approval polling
    let message: String?     // Error message (when status == "error")
    let tan_medium_required: Bool? // true when bank needs TAN medium selection

    var isOk: Bool { status == "ok" }
    var needsTan: Bool { status == "tan_required" }
    var isError: Bool { status == "error" }
}

struct TanMediumInfo: Codable, Identifiable {
    let name: String
    let status: Int  // 1 = active, 0 = inactive

    var id: String { name }
}

struct FintsTanMediaResult: Codable {
    let status: String
    let media: [TanMediumInfo]?
    let message: String?

    var isOk: Bool { status == "ok" }
}

struct FintsFetchResult: Codable {
    // When fetch succeeds
    let imported: Int?
    let duplicates: Int?

    // When TAN is required mid-fetch
    let status: String?
    let challenge: String?
    let phototan: String?
    let decoupled: Bool?
    let message: String?

    var needsTan: Bool { status == "tan_required" }
    var isError: Bool { status == "error" }
}
