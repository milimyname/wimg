import SwiftUI
import WimgI18n

/// Full-screen lock that gates the app behind Face ID / Touch ID / passcode.
/// Shows the wimg mark and a single Entsperren button that re-triggers the
/// biometric prompt.
struct LockScreen: View {
    @ObservedObject var lock: BiometricLock

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WimgTheme.accent.opacity(0.2))
                    .frame(width: 112, height: 112)
                Image(systemName: iconName)
                    .font(.system(size: 44))
                    .foregroundStyle(WimgTheme.text.opacity(0.8))
            }

            VStack(spacing: 8) {
                Text("wimg")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                Text(#L("App ist gesperrt"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
            }

            Spacer()

            Button {
                Task { await lock.authenticate() }
            } label: {
                Text(#L("Entsperren"))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.heroText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(WimgTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WimgTheme.bg)
        .task {
            // Auto-prompt once on appear — same behavior as Banking apps.
            await lock.authenticate()
        }
    }

    private var iconName: String {
        switch lock.availableMethod {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .passcode: return "lock.fill"
        case .none: return "lock.fill"
        }
    }
}

/// Blank/blur overlay shown while the app is `.inactive` (mid-transition
/// or showing the app switcher). Prevents the system snapshot from
/// containing transaction data.
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            WimgTheme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(WimgTheme.accent.opacity(0.2))
                        .frame(width: 88, height: 88)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(WimgTheme.text.opacity(0.7))
                }
                Text("wimg")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(WimgTheme.text)
            }
        }
    }
}
