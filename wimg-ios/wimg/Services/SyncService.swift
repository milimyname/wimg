import Foundation

/// URLSession-based sync client with real-time WebSocket support.
/// Mirrors wimg-web/src/lib/sync.ts + sync-ws.svelte.ts.
actor SyncService {
    static let shared = SyncService()

    private let baseURL = WimgConfig.syncBaseURL
    private let keyDefault = WimgConfig.udSyncKey
    private let tsDefault = WimgConfig.udSyncLastTS

    private var wsTask: URLSessionWebSocketTask?
    private var reconnectDelay: TimeInterval = 1.0
    private var isClosed = false
    private var pingTimer: Task<Void, Never>?

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

    // MARK: - HTTP Push/Pull

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

        // Also broadcast via WebSocket for real-time delivery
        pushChangesViaWS(changes)

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

    // MARK: - WebSocket

    func connectWebSocket() {
        guard let key = syncKey else { return }
        isClosed = false
        doConnect(key: key)
    }

    func disconnectWebSocket() {
        isClosed = true
        pingTimer?.cancel()
        pingTimer = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
    }

    private func doConnect(key: String) {
        guard !isClosed else { return }

        let wsURL = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(wsURL)/ws/\(key)") else { return }

        let session = URLSession(configuration: .default)
        wsTask = session.webSocketTask(with: url)
        wsTask?.resume()

        reconnectDelay = 1.0
        receiveLoop(key: key)
    }

    private func receiveLoop(key: String) {
        wsTask?.receive { [weak self] result in
            guard let self else { return }

            Task {
                await self.handleReceiveResult(result, key: key)
            }
        }
    }

    private func handleReceiveResult(_ result: Result<URLSessionWebSocketTask.Message, Error>, key: String) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                handleMessage(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }
            @unknown default:
                break
            }
            receiveLoop(key: key)

        case .failure:
            guard !isClosed else { return }
            // Reconnect with exponential backoff
            let delay = reconnectDelay
            reconnectDelay = min(reconnectDelay * 2, 30.0)

            Task {
                try? await Task.sleep(for: .seconds(delay))
                await doConnect(key: key)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(WSMessage.self, from: data) else {
            return
        }

        switch msg.type {
        case "changes":
            guard let rows = msg.rows, !rows.isEmpty else { return }
            // Apply changes to local database
            _ = try? LibWimg.applyChanges(rows)
            // Notify all views to refresh
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
            }

        case "ping":
            // Respond with pong
            let pong = #"{"type":"pong"}"#
            wsTask?.send(.string(pong)) { _ in }

        case "push_ack":
            break // Acknowledgement of our push

        default:
            break
        }
    }

    private func pushChangesViaWS(_ rows: [LibWimg.SyncRow]) {
        guard let wsTask, wsTask.state == .running else { return }

        struct WSPush: Encodable {
            let type = "push"
            let rows: [LibWimg.SyncRow]
        }

        guard let data = try? JSONEncoder().encode(WSPush(rows: rows)),
              let text = String(data: data, encoding: .utf8) else { return }

        wsTask.send(.string(text)) { error in
            if let error {
                print("[wimg-sync] WS push failed: \(error)")
            }
        }
    }
}

// MARK: - WebSocket Message

private struct WSMessage: Decodable {
    let type: String
    let rows: [LibWimg.SyncRow]?
    let merged: Int?
}

// MARK: - Errors

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
