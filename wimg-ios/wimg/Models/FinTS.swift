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
    let message: String?     // Error message (when status == "error")

    var isOk: Bool { status == "ok" }
    var needsTan: Bool { status == "tan_required" }
    var isError: Bool { status == "error" }
}

struct FintsFetchResult: Codable {
    // When fetch succeeds
    let imported: Int?
    let duplicates: Int?

    // When TAN is required mid-fetch
    let status: String?
    let challenge: String?

    var needsTan: Bool { status == "tan_required" }
}
