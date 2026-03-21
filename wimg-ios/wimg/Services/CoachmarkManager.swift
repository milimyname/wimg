import Foundation

@Observable
class CoachmarkManager {
    static let shared = CoachmarkManager()

    private let prefix = "wimg_coachmark_"

    func shouldShow(_ key: String) -> Bool {
        !UserDefaults.standard.bool(forKey: prefix + key)
    }

    func dismiss(_ key: String) {
        UserDefaults.standard.set(true, forKey: prefix + key)
    }
}
