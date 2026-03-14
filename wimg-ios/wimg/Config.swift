import Foundation

/// Centralized configuration — all URLs, keys, and constants in one place.
enum WimgConfig {
    // MARK: - Sync API

    #if DEBUG
    static let syncBaseURL = "http://localhost:8787"
    #else
    static let syncBaseURL = "https://wimg-sync.mili-my.name"
    #endif

    // MARK: - GitHub

    static let releasesURL = "https://github.com/milimyname/wimg/releases"

    // MARK: - UserDefaults keys

    static let udSyncKey = "wimg_sync_key"
    static let udSyncLastTS = "wimg_sync_last_ts"
    static let udFeatures = "wimg_features"

    // MARK: - Feature Flags (default: all ON for existing users)

    static let defaultFeatures: [String: Bool] = [
        "debts": true,
        "recurring": true,
        "review": true,
        "goals": true,
        "tax": true,
    ]
}
