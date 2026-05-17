import Foundation
import LocalAuthentication
import SwiftUI

/// Biometric (Face ID / Touch ID) app lock.
///
/// Locks the app behind `LAContext.evaluatePolicy` on cold start, when
/// returning from background, and when re-enabling the toggle. Falls back
/// to device passcode if biometrics aren't enrolled.
///
/// Toggle persisted in `@AppStorage("wimg_lock_enabled")`. Defaults off so
/// no one is surprised — opt-in from Settings.
@MainActor
final class BiometricLock: ObservableObject {
    static let shared = BiometricLock()

    /// True when the gate is up and the main UI should be hidden.
    @Published var isLocked: Bool = UserDefaults.standard.bool(forKey: "wimg_lock_enabled")

    /// True while a privacy overlay should cover the screen (e.g. app
    /// switcher preview). Independent of `isLocked` — the overlay is the
    /// short-lived blank shown when going to background, the lock is the
    /// gate shown when coming back.
    @Published var showPrivacyOverlay: Bool = false

    /// When the app was last sent to background. `nil` while foreground.
    /// Used to apply a grace period before re-locking — quick context
    /// switches (control center, glance at a notification, brief tab to
    /// password manager) don't fire the lock; only absences longer than
    /// `backgroundGrace` do. Mirrors the web build's 30-second grace.
    private var backgroundedAt: Date?
    private let backgroundGrace: TimeInterval = 30

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "wimg_lock_enabled")
    }

    enum AvailableMethod {
        case faceID, touchID, passcode, none
    }

    var availableMethod: AvailableMethod {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            // Fall back to device passcode if biometrics unavailable.
            if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
                return .passcode
            }
            return .none
        }
        switch ctx.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "wimg_lock_enabled")
        // Engage the lock screen immediately so the user sees Face ID fire
        // right after flipping the toggle — otherwise they'd have to
        // background+foreground the app first, which feels broken.
        isLocked = enabled
    }

    /// Trigger the biometric prompt. On success, unlocks. On failure, stays
    /// locked — the user can retry from the lock screen.
    func authenticate() async {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = NSLocalizedString("Code verwenden", comment: "")
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(policy, error: &err) else { return }
        do {
            let reason = NSLocalizedString("App entsperren", comment: "")
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: reason)
            if ok { isLocked = false }
        } catch {
            // Cancel / failed — leave locked.
        }
    }

    /// Called from the scene-phase observer.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            showPrivacyOverlay = true
            // Record the start of a background interval instead of locking
            // immediately. The lock is decided when we come back to .active.
            if isEnabled, backgroundedAt == nil {
                backgroundedAt = Date()
            }
        case .inactive:
            // App switcher snapshot is taken in `.inactive` — cover the UI.
            showPrivacyOverlay = true
        case .active:
            showPrivacyOverlay = false
            if isEnabled, let at = backgroundedAt {
                let elapsed = Date().timeIntervalSince(at)
                if elapsed >= backgroundGrace {
                    isLocked = true
                }
            }
            backgroundedAt = nil
        @unknown default:
            break
        }
    }
}
