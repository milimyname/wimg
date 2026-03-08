import SwiftUI

@Observable
class FeatureFlags {
    static let shared = FeatureFlags()

    private(set) var features: [String: Bool]

    private init() {
        if let data = UserDefaults.standard.data(forKey: WimgConfig.udFeatures),
           let stored = try? JSONDecoder().decode([String: Bool].self, from: data) {
            features = WimgConfig.defaultFeatures.merging(stored) { _, new in new }
        } else {
            features = WimgConfig.defaultFeatures
        }
    }

    func isEnabled(_ key: String) -> Bool {
        features[key] ?? false
    }

    func toggle(_ key: String) {
        features[key] = !(features[key] ?? false)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(features) {
            UserDefaults.standard.set(data, forKey: WimgConfig.udFeatures)
        }
    }
}
