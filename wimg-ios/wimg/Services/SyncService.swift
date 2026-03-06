import Foundation

/// URLSession-based sync client. Mirrors wimg-web/src/lib/sync.ts.
actor SyncService {
    static let shared = SyncService()

    private let baseURL = WimgConfig.syncBaseURL
    private let keyDefault = WimgConfig.udSyncKey
    private let tsDefault = WimgConfig.udSyncLastTS

    var syncKey: String? {
        get { UserDefaults.standard.string(forKey: keyDefault) }
    }

    var lastSyncTimestamp: Int {
        get { UserDefaults.standard.integer(forKey: tsDefault) }
    }

    var isEnabled: Bool { syncKey != nil }

    nonisolated func setSyncKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: keyDefault)
    }

    nonisolated func clearSyncKey() {
        UserDefaults.standard.removeObject(forKey: keyDefault)
        UserDefaults.standard.removeObject(forKey: tsDefault)
    }

    private nonisolated func setLastSync(_ ts: Int) {
        UserDefaults.standard.set(ts, forKey: tsDefault)
    }

    func push() async throws -> Int {
        guard let key = syncKey else { throw SyncError.noKey }

        let changes = LibWimg.getChanges(sinceMs: lastSyncTimestamp)
        if changes.isEmpty { return 0 }

        let payload = LibWimg.SyncPayload(rows: changes)
        let body = try JSONEncoder().encode(payload)

        var request = URLRequest(url: URL(string: "\(baseURL)/sync/\(key)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pushFailed(String(data: data, encoding: .utf8) ?? "")
        }

        struct MergeResult: Decodable { let merged: Int }
        let result = try JSONDecoder().decode(MergeResult.self, from: data)
        return result.merged
    }

    func pull() async throws -> Int {
        guard let key = syncKey else { throw SyncError.noKey }

        let since = lastSyncTimestamp
        let url = URL(string: "\(baseURL)/sync/\(key)?since=\(since)")!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pullFailed(String(data: data, encoding: .utf8) ?? "")
        }

        let payload = try JSONDecoder().decode(LibWimg.SyncPayload.self, from: data)
        if payload.rows.isEmpty { return 0 }

        let applied = try LibWimg.applyChanges(payload.rows)
        setLastSync(Int(Date().timeIntervalSince1970 * 1000))
        return applied
    }

    func syncFull() async throws -> (pushed: Int, pulled: Int) {
        let pushed = try await push()
        let pulled = try await pull()
        setLastSync(Int(Date().timeIntervalSince1970 * 1000))
        return (pushed, pulled)
    }
}

enum SyncError: LocalizedError {
    case noKey
    case pushFailed(String)
    case pullFailed(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "Kein Sync-Schlüssel konfiguriert"
        case .pushFailed(let msg): "Push fehlgeschlagen: \(msg)"
        case .pullFailed(let msg): "Pull fehlgeschlagen: \(msg)"
        }
    }
}
