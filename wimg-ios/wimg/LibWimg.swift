import Foundation

/// Swift wrapper over libwimg C ABI. Mirrors wimg-web/src/lib/wasm.ts.
/// Pattern: call C function -> get pointer to length-prefixed JSON -> decode -> free pointer.
final class LibWimg {
    private init() {}

    private static var isInitialized = false

    // MARK: - Lifecycle

    static func initialize() throws {
        let dbPath = Self.dbPath()
        try dbPath.withCString { cPath in
            let rc = wimg_init(cPath)
            if rc != 0 {
                throw WimgError.initFailed(lastError())
            }
        }
        isInitialized = true
    }

    static func close() {
        wimg_close()
        isInitialized = false
    }

    // MARK: - Parse & Import

    static func parseCSV(_ data: Data) throws -> ParseResult {
        try ensureInit()
        return try data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WimgError.allocationFailed
            }
            guard let resultPtr = wimg_parse_csv(ptr, UInt32(data.count)) else {
                throw WimgError.importFailed(lastError())
            }
            defer { wimg_free(resultPtr, 0) }
            return try decodeLengthPrefixed(resultPtr)
        }
    }

    static func importCSV(_ data: Data) throws -> ImportResult {
        try ensureInit()
        return try data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WimgError.allocationFailed
            }
            guard let resultPtr = wimg_import_csv(ptr, UInt32(data.count)) else {
                throw WimgError.importFailed(lastError())
            }
            defer { wimg_free(resultPtr, 0) }
            return try decodeLengthPrefixed(resultPtr)
        }
    }

    // MARK: - Transactions

    static func getTransactions() -> [Transaction] {
        guard isInitialized else { return [] }
        guard let ptr = wimg_get_transactions() else { return [] }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? []
    }

    static func setCategory(id: String, category: UInt8) throws {
        try ensureInit()
        let idData = Array(id.utf8)
        let rc = idData.withUnsafeBufferPointer { buf in
            wimg_set_category(buf.baseAddress!, UInt32(buf.count), category)
        }
        if rc != 0 {
            throw WimgError.operationFailed("setCategory", lastError())
        }
    }

    static func autoCategorize() -> Int {
        guard isInitialized else { return 0 }
        let result = wimg_auto_categorize()
        return Int(max(result, 0))
    }

    // MARK: - Summaries

    static func getSummary(year: Int, month: Int) -> MonthlySummary {
        guard isInitialized else {
            return MonthlySummary(year: year, month: month, income: 0, expenses: 0, available: 0, tx_count: 0, by_category: [])
        }
        guard let ptr = wimg_get_summary(UInt32(year), UInt32(month)) else {
            return MonthlySummary(year: year, month: month, income: 0, expenses: 0, available: 0, tx_count: 0, by_category: [])
        }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? MonthlySummary(year: year, month: month, income: 0, expenses: 0, available: 0, tx_count: 0, by_category: [])
    }

    // MARK: - Debts

    static func getDebts() -> [Debt] {
        guard isInitialized else { return [] }
        guard let ptr = wimg_get_debts() else { return [] }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? []
    }

    static func addDebt(name: String, total: Double, monthly: Double) throws {
        try ensureInit()
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32)
        let json = """
        {"id":"\(id)","name":"\(name)","total":\(total),"monthly":\(monthly)}
        """
        let data = Array(json.utf8)
        let rc = data.withUnsafeBufferPointer { buf in
            wimg_add_debt(buf.baseAddress!, UInt32(buf.count))
        }
        if rc != 0 {
            throw WimgError.operationFailed("addDebt", lastError())
        }
    }

    static func markDebtPaid(id: String, amountCents: Int) throws {
        try ensureInit()
        let idData = Array(id.utf8)
        let rc = idData.withUnsafeBufferPointer { buf in
            wimg_mark_debt_paid(buf.baseAddress!, UInt32(buf.count), Int64(amountCents))
        }
        if rc != 0 {
            throw WimgError.operationFailed("markDebtPaid", lastError())
        }
    }

    static func deleteDebt(id: String) throws {
        try ensureInit()
        let idData = Array(id.utf8)
        let rc = idData.withUnsafeBufferPointer { buf in
            wimg_delete_debt(buf.baseAddress!, UInt32(buf.count))
        }
        if rc != 0 {
            throw WimgError.operationFailed("deleteDebt", lastError())
        }
    }

    // MARK: - Undo/Redo

    struct UndoResult: Codable {
        let op: String
        let table: String
        let row_id: String
        let column: String?
    }

    static func undo() -> UndoResult? {
        guard isInitialized else { return nil }
        guard let ptr = wimg_undo() else { return nil }
        defer { wimg_free(ptr, 0) }
        return try? decodeLengthPrefixed(ptr)
    }

    static func redo() -> UndoResult? {
        guard isInitialized else { return nil }
        guard let ptr = wimg_redo() else { return nil }
        defer { wimg_free(ptr, 0) }
        return try? decodeLengthPrefixed(ptr)
    }

    // MARK: - Private Helpers

    private static func dbPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("wimg.db").path
    }

    private static func ensureInit() throws {
        if !isInitialized {
            throw WimgError.notInitialized
        }
    }

    /// Read a length-prefixed string (4 bytes LE length + data) and decode as JSON.
    private static func decodeLengthPrefixed<T: Decodable>(_ ptr: UnsafePointer<UInt8>) throws -> T {
        let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        let data = Data(bytes: ptr.advanced(by: 4), count: Int(len))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func lastError() -> String {
        guard let ptr = wimg_get_error() else { return "Unknown error" }
        let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        let data = Data(bytes: ptr.advanced(by: 4), count: Int(len))
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}

enum WimgError: LocalizedError {
    case notInitialized
    case initFailed(String)
    case allocationFailed
    case importFailed(String)
    case operationFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: "Database not initialized"
        case .initFailed(let msg): "Init failed: \(msg)"
        case .allocationFailed: "Memory allocation failed"
        case .importFailed(let msg): "Import failed: \(msg)"
        case .operationFailed(let op, let msg): "\(op) failed: \(msg)"
        }
    }
}
