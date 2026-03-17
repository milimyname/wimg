import Foundation
import Security

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

        // Set HTTP callback for FinTS (uses URLSession for native TLS)
        wimg_set_http_callback { url, urlLen, body, bodyLen, outBuf, outBufLen in
            guard let url, let body, let outBuf else {
                print("[FinTS HTTP] callback received nil pointers")
                return -1
            }

            let urlStr = String(bytes: UnsafeBufferPointer(start: url, count: Int(urlLen)), encoding: .utf8) ?? ""
            let bodyData = Data(bytes: body, count: Int(bodyLen))

            guard let requestUrl = URL(string: urlStr) else {
                print("[FinTS HTTP] invalid URL: \(urlStr)")
                return -1
            }

            print("[FinTS HTTP] POST \(urlStr) (\(bodyData.count) bytes)")

            var request = URLRequest(url: requestUrl)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            // Synchronous request on a dedicated queue (FinTS calls are blocking from Zig)
            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var responseError: Error?

            let session = URLSession(configuration: .ephemeral)
            session.dataTask(with: request) { data, response, error in
                responseData = data
                responseError = error
                if let httpResponse = response as? HTTPURLResponse {
                    print("[FinTS HTTP] response: \(httpResponse.statusCode), \(data?.count ?? 0) bytes")
                    if let data, data.count > 0, data.count < 500 {
                        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
                        print("[FinTS HTTP] body preview: \(preview)")
                    }
                }
                semaphore.signal()
            }.resume()

            let waitResult = semaphore.wait(timeout: .now() + 35)
            if waitResult == .timedOut {
                print("[FinTS HTTP] request timed out after 35s")
                session.invalidateAndCancel()
                return -1
            }

            if let error = responseError {
                print("[FinTS HTTP] error: \(error.localizedDescription)")
                return -1
            }
            guard let data = responseData else {
                print("[FinTS HTTP] no response data")
                return -1
            }
            guard data.count <= outBufLen else {
                print("[FinTS HTTP] response too large: \(data.count) > \(outBufLen)")
                return -1
            }

            data.copyBytes(to: outBuf, count: data.count)
            return Int32(data.count)
        }
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

    static func getTransactions() throws -> [Transaction] {
        try getTransactionsFiltered(account: nil)
    }

    static func getTransactionsFiltered(account: String?) throws -> [Transaction] {
        guard isInitialized else { return [] }
        let acctData = Array((account ?? "").utf8)
        let ptr: UnsafePointer<UInt8>? = acctData.withUnsafeBufferPointer { buf in
            wimg_get_transactions_filtered(buf.baseAddress!, UInt32(buf.count))
        }
        guard let ptr else {
            let err = lastError()
            if err.contains("buffer too small") {
                throw WimgError.operationFailed("getTransactions", "Zu viele Transaktionen zum Anzeigen. Daten sind gespeichert, aber der Anzeigepuffer ist voll.")
            }
            return []
        }
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

    static func setExcluded(id: String, excluded: Bool) throws {
        try ensureInit()
        let idData = Array(id.utf8)
        let rc = idData.withUnsafeBufferPointer { buf in
            wimg_set_excluded(buf.baseAddress!, UInt32(buf.count), excluded ? 1 : 0)
        }
        if rc != 0 {
            throw WimgError.operationFailed("setExcluded", lastError())
        }
    }

    static func autoCategorize() -> Int {
        guard isInitialized else { return 0 }
        let result = wimg_auto_categorize()
        return Int(max(result, 0))
    }

    // MARK: - Summaries

    static func getSummary(year: Int, month: Int) -> MonthlySummary {
        getSummaryFiltered(year: year, month: month, account: nil)
    }

    static func getSummaryFiltered(year: Int, month: Int, account: String?) -> MonthlySummary {
        let empty = MonthlySummary(year: year, month: month, income: 0, expenses: 0, available: 0, tx_count: 0, by_category: [])
        guard isInitialized else { return empty }
        let acctData = Array((account ?? "").utf8)
        let ptr: UnsafePointer<UInt8>? = acctData.withUnsafeBufferPointer { buf in
            wimg_get_summary_filtered(UInt32(year), UInt32(month), buf.baseAddress!, UInt32(buf.count))
        }
        guard let ptr else { return empty }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? empty
    }

    // MARK: - Recurring

    static func getRecurring() -> [RecurringPattern] {
        guard isInitialized else { return [] }
        guard let ptr = wimg_get_recurring() else { return [] }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? []
    }

    @discardableResult
    static func detectRecurring() -> Int {
        guard isInitialized else { return 0 }
        let result = wimg_detect_recurring()
        return Int(max(result, 0))
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

    // MARK: - Savings Goals

    static func getGoals() -> [Goal] {
        guard isInitialized else { return [] }
        guard let ptr = wimg_get_goals() else { return [] }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? []
    }

    static func addGoal(name: String, icon: String, target: Double, deadline: String?) throws {
        try ensureInit()
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32)
        let targetCents = Int(target * 100)
        let deadlineJson = deadline.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"id":"\(id)","name":"\(name)","icon":"\(icon)","target":\(targetCents),"deadline":\(deadlineJson)}
        """
        let data = Array(json.utf8)
        let rc = data.withUnsafeBufferPointer { buf in
            wimg_add_goal(buf.baseAddress!, UInt32(buf.count))
        }
        if rc != 0 {
            throw WimgError.operationFailed("addGoal", lastError())
        }
    }

    static func contributeGoal(id: String, amountCents: Int) throws {
        try ensureInit()
        let idData = Array(id.utf8)
        let rc = idData.withUnsafeBufferPointer { buf in
            wimg_contribute_goal(buf.baseAddress!, UInt32(buf.count), Int64(amountCents))
        }
        if rc != 0 {
            throw WimgError.operationFailed("contributeGoal", lastError())
        }
    }

    static func deleteGoal(id: String) throws {
        try ensureInit()
        let idData = Array(id.utf8)
        let rc = idData.withUnsafeBufferPointer { buf in
            wimg_delete_goal(buf.baseAddress!, UInt32(buf.count))
        }
        if rc != 0 {
            throw WimgError.operationFailed("deleteGoal", lastError())
        }
    }

    // MARK: - Accounts

    static func getAccounts() -> [Account] {
        guard isInitialized else { return [] }
        guard let ptr = wimg_get_accounts() else { return [] }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? []
    }

    static func addAccount(id: String, name: String, color: String) throws {
        try ensureInit()
        let json = """
        {"id":"\(id)","name":"\(name)","bank":"","color":"\(color)"}
        """
        let data = Array(json.utf8)
        let rc = data.withUnsafeBufferPointer { buf in
            wimg_add_account(buf.baseAddress!, UInt32(buf.count))
        }
        if rc != 0 {
            throw WimgError.operationFailed("addAccount", lastError())
        }
    }

    static func updateAccount(id: String, name: String, color: String) throws {
        try ensureInit()
        let json = """
        {"id":"\(id)","name":"\(name)","bank":"","color":"\(color)"}
        """
        let data = Array(json.utf8)
        let rc = data.withUnsafeBufferPointer { buf in
            wimg_update_account(buf.baseAddress!, UInt32(buf.count))
        }
        if rc != 0 {
            throw WimgError.operationFailed("updateAccount", lastError())
        }
    }

    static func deleteAccount(id: String) throws {
        try ensureInit()
        let idData = Array(id.utf8)
        let rc = idData.withUnsafeBufferPointer { buf in
            wimg_delete_account(buf.baseAddress!, UInt32(buf.count))
        }
        if rc != 0 {
            throw WimgError.operationFailed("deleteAccount", lastError())
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

    // MARK: - Sync

    struct SyncRow: Codable {
        let table: String
        let id: String
        let data: [String: AnyCodable]
        let updated_at: Int
    }

    struct SyncPayload: Codable {
        let rows: [SyncRow]
    }

    static func getChanges(sinceMs: Int) -> [SyncRow] {
        guard isInitialized else { return [] }
        guard let ptr = wimg_get_changes(Int64(sinceMs)) else { return [] }
        defer { wimg_free(ptr, 0) }
        let payload: SyncPayload? = try? decodeLengthPrefixed(ptr)
        return payload?.rows ?? []
    }

    static func applyChanges(_ rows: [SyncRow]) throws -> Int {
        try ensureInit()
        let payload = SyncPayload(rows: rows)
        let data = try JSONEncoder().encode(payload)
        let rc = Array(data).withUnsafeBufferPointer { buf in
            wimg_apply_changes(buf.baseAddress!, UInt32(buf.count))
        }
        if rc < 0 {
            throw WimgError.operationFailed("applyChanges", lastError())
        }
        return Int(rc)
    }

    // MARK: - Crypto (E2E encryption for sync)

    /// Derive a 32-byte encryption key from a sync key using HKDF-SHA256.
    static func deriveEncryptionKey(syncKey: String) -> Data? {
        let keyBytes = Array(syncKey.utf8)
        let ptr = keyBytes.withUnsafeBufferPointer { buf in
            wimg_derive_key(buf.baseAddress!, UInt32(buf.count))
        }
        guard let ptr else { return nil }
        defer { wimg_free(ptr, 0) }
        let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        return Data(bytes: ptr.advanced(by: 4), count: Int(len))
    }

    /// Encrypt a plaintext string using XChaCha20-Poly1305. Returns base64-encoded ciphertext.
    static func encryptField(plaintext: String, key: Data) -> String? {
        let ptBytes = Array(plaintext.utf8)
        var nonce = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, 24, &nonce)

        let result = ptBytes.withUnsafeBufferPointer { ptBuf in
            key.withUnsafeBytes { keyBuf in
                nonce.withUnsafeBufferPointer { nonceBuf in
                    wimg_encrypt_field(
                        ptBuf.baseAddress!, UInt32(ptBuf.count),
                        keyBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        nonceBuf.baseAddress!
                    )
                }
            }
        }
        guard let result else { return nil }
        defer { wimg_free(result, 0) }
        return readLengthPrefixedString(result)
    }

    /// Decrypt a base64-encoded ciphertext using XChaCha20-Poly1305. Returns plaintext string.
    static func decryptField(ciphertext: String, key: Data) -> String? {
        let ctBytes = Array(ciphertext.utf8)
        let result = ctBytes.withUnsafeBufferPointer { ctBuf in
            key.withUnsafeBytes { keyBuf in
                wimg_decrypt_field(
                    ctBuf.baseAddress!, UInt32(ctBuf.count),
                    keyBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                )
            }
        }
        guard let result else { return nil }
        defer { wimg_free(result, 0) }
        return readLengthPrefixedString(result)
    }

    // MARK: - FinTS (native-only bank connection)

    static func fintsGetBanks() -> [BankInfo] {
        guard let ptr = wimg_fints_get_banks() else { return [] }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? []
    }

    static func fintsConnect(blz: String, user: String, pin: String, product: String = "F7C4049477F6136957A46EC28") throws -> FintsStatusResult {
        try ensureInit()
        let json = """
        {"blz":"\(blz)","user":"\(user)","pin":"\(pin)","product":"\(product)"}
        """
        let data = Array(json.utf8)
        let ptr: UnsafePointer<UInt8>? = data.withUnsafeBufferPointer { buf in
            wimg_fints_connect(buf.baseAddress!, UInt32(buf.count))
        }
        guard let ptr else {
            throw WimgError.operationFailed("fintsConnect", lastError())
        }
        defer { wimg_free(ptr, 0) }
        return try decodeLengthPrefixed(ptr)
    }

    static func fintsSendTan(tan: String) throws -> FintsStatusResult {
        try ensureInit()
        let json = """
        {"tan":"\(tan)"}
        """
        let data = Array(json.utf8)
        let ptr: UnsafePointer<UInt8>? = data.withUnsafeBufferPointer { buf in
            wimg_fints_send_tan(buf.baseAddress!, UInt32(buf.count))
        }
        guard let ptr else {
            throw WimgError.operationFailed("fintsSendTan", lastError())
        }
        defer { wimg_free(ptr, 0) }
        return try decodeLengthPrefixed(ptr)
    }

    static func fintsFetch(from: String, to: String) throws -> FintsFetchResult {
        try ensureInit()
        let json = """
        {"from":"\(from)","to":"\(to)"}
        """
        let data = Array(json.utf8)
        let ptr: UnsafePointer<UInt8>? = data.withUnsafeBufferPointer { buf in
            wimg_fints_fetch(buf.baseAddress!, UInt32(buf.count))
        }
        guard let ptr else {
            throw WimgError.operationFailed("fintsFetch", lastError())
        }
        defer { wimg_free(ptr, 0) }
        return try decodeLengthPrefixed(ptr)
    }

    // MARK: - Snapshots

    static func takeSnapshot(year: Int, month: Int) throws {
        try ensureInit()
        let rc = wimg_take_snapshot(UInt32(year), UInt32(month))
        if rc != 0 {
            throw WimgError.operationFailed("takeSnapshot", lastError())
        }
    }

    static func getSnapshots() -> [Snapshot] {
        guard isInitialized else { return [] }
        guard let ptr = wimg_get_snapshots() else { return [] }
        defer { wimg_free(ptr, 0) }
        return (try? decodeLengthPrefixed(ptr)) ?? []
    }

    // MARK: - Export

    static func exportCsv() -> String? {
        guard isInitialized else { return nil }
        guard let ptr = wimg_export_csv() else { return nil }
        defer { wimg_free(ptr, 0) }
        return readLengthPrefixedString(ptr)
    }

    static func exportDb() -> String? {
        guard isInitialized else { return nil }
        guard let ptr = wimg_export_db() else { return nil }
        defer { wimg_free(ptr, 0) }
        return readLengthPrefixedString(ptr)
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

    /// Read a length-prefixed raw string (4 bytes LE length + data).
    private static func readLengthPrefixedString(_ ptr: UnsafePointer<UInt8>) -> String? {
        let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        let data = Data(bytes: ptr.advanced(by: 4), count: Int(len))
        return String(data: data, encoding: .utf8)
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
