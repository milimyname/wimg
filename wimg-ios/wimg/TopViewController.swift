import UIKit

extension UIApplication {
    /// The view controller currently on top of the presentation stack of the
    /// foreground key window. Walking the `presentedViewController` chain (and
    /// into nav/tab containers) is required because presenting on
    /// `windows.first?.rootViewController` silently fails when that window isn't
    /// key, or when the root already has something presented (e.g. a sheet).
    var topViewController: UIViewController? {
        let keyWindow = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first

        var top = keyWindow?.rootViewController
        while true {
            if let presented = top?.presentedViewController {
                top = presented
            } else if let nav = top as? UINavigationController {
                top = nav.visibleViewController ?? nav
                if top?.presentedViewController == nil { break }
            } else if let tab = top as? UITabBarController {
                top = tab.selectedViewController ?? tab
                if top?.presentedViewController == nil { break }
            } else {
                break
            }
        }
        return top
    }
}
