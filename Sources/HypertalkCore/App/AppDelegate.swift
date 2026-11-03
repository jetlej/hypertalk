import AppKit

/// Opening Hypertalk again while it runs (from Applications, Spotlight or
/// Launchpad) shows Settings: the way back in when the menu-bar icon is out
/// of sight on a crowded menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NSApp.delegate` is weak; this keeps the one instance alive.
    private static var current: AppDelegate?

    private let onReopen: () -> Void

    private init(onReopen: @escaping () -> Void) {
        self.onReopen = onReopen
    }

    static func install(onReopen: @escaping () -> Void) {
        let delegate = AppDelegate(onReopen: onReopen)
        current = delegate
        NSApp.delegate = delegate
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onReopen()
        return false
    }
}
