import AppKit

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
///
/// The menu has named slots, top to bottom: `statusLine`, `modelLine`,
/// `grantPermissionsItem`, `settingsItem`, `checkForUpdatesItem`, `quitItem`. Features update a slot
/// rather than rebuilding the menu.
@MainActor
final class MenuBarController {
    private static func readyStatus(_ key: HotkeyKey) -> String { "idle · hold \(key.shortName) to dictate" }

    private let statusItem: NSStatusItem
    /// Slot: what the dictation loop is doing. Driven as a `DictationObserver`.
    let statusLine: NSMenuItem
    /// Slot: the loaded model.
    let modelLine: NSMenuItem
    /// Slot: reopens the onboarding window (#51). Shown in Hypertalk.app while
    /// a permission is missing.
    let grantPermissionsItem: NSMenuItem
    /// What `grantPermissionsItem` does; set by `OnboardingWindow`.
    var onGrantPermissions: (() -> Void)?
    /// Slot: opens the Settings window (#41) through `onOpenSettings`.
    let settingsItem: NSMenuItem
    /// Called by Settings…; set by the daemon, which owns the window.
    var onOpenSettings: (() -> Void)?
    /// Slot: asks Sparkle to check now. Hidden unless the updater is running,
    /// which it is only in Hypertalk.app's release builds.
    let checkForUpdatesItem: NSMenuItem
    /// Slot: quits hypertalk.
    let quitItem: NSMenuItem

    /// A degraded hotkey tap replaces the idle line, so the menu bar does not
    /// claim fn works when it does not (#37).
    private var hotkeyHealth: HotkeyHealth = .ok
    /// The key the idle line tells the user to hold (#42).
    private var hotkey: HotkeyKey = .fn
    private var isIdle = true
    private var idleStatus: String { hotkeyHealth.statusText ?? Self.readyStatus(hotkey) }

    init(modelID: String) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLine = NSMenuItem(title: Self.readyStatus(.fn), action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        modelLine = NSMenuItem(title: "model: \(modelID)", action: nil, keyEquivalent: "")
        modelLine.isEnabled = false
        menu.addItem(modelLine)

        grantPermissionsItem = NSMenuItem(
            title: "Grant Permissions…",
            action: #selector(grantPermissionsClicked),
            keyEquivalent: ""
        )
        grantPermissionsItem.isHidden = true
        menu.addItem(grantPermissionsItem)

        menu.addItem(.separator())

        settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        menu.addItem(settingsItem)

        checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesClicked),
            keyEquivalent: ""
        )
        checkForUpdatesItem.isHidden = !Updater.isRunning
        menu.addItem(checkForUpdatesItem)

        quitItem = NSMenuItem(
            title: "Quit hypertalk",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        quitItem.target = self
        settingsItem.target = self
        checkForUpdatesItem.target = self
        grantPermissionsItem.target = self
        configureButton()
    }

    func setStatus(_ text: String) {
        statusLine.title = text
    }

    func setHotkeyHealth(_ health: HotkeyHealth) {
        hotkeyHealth = health
        if isIdle { setStatus(idleStatus) }
    }

    func setHotkey(_ key: HotkeyKey) {
        hotkey = key
        if isIdle { setStatus(idleStatus) }
    }

    func setModel(_ modelID: String) {
        modelLine.title = "model: \(modelID)"
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // Menu-bar status icons are nominally 18pt tall; the bubble fills it.
        button.image = Self.logo(side: 18)
    }

    // The logo: a chat bubble with a bolt cut out of it. Inlined SVG, so
    // the executable has no separate resource bundle to install alongside
    // it — true single-binary. The viewBox is cropped to the bubble.
    nonisolated static let bubbleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="2.8 2.6 18.4 18.4">\
    <path d="M12 3.2c5 0 9 3.4 9 7.6s-4 7.6-9 7.6c-1 0-2-.1-2.9-.4L4.6 20.4l1.2-3.9C4.1 15.1 3 13.1 3 10.8 3 6.6 7 3.2 12 3.2z"/>\
    </svg>
    """

    // Tabler Icons "bolt" (filled), MIT License, https://tabler.io/icons.
    nonisolated static let boltSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\
    <path d="M13 2l.018 .001l.016 .001l.083 .005l.011 .002h.011l.038 .009l.052 .008l.016 .006l.011 .001l.029 .011l.052 .014l.019 .009l.015 .004l.028 .014l.04 .017l.021 .012l.022 .01l.023 .015l.031 .017l.034 .024l.018 .011l.013 .012l.024 .017l.038 .034l.022 .017l.008 .01l.014 .012l.036 .041l.026 .027l.006 .009c.12 .147 .196 .322 .218 .513l.001 .012l.002 .041l.004 .064v6h5a1 1 0 0 1 .868 1.497l-.06 .091l-8 11c-.568 .783 -1.808 .38 -1.808 -.588v-6h-5a1 1 0 0 1 -.868 -1.497l.06 -.091l8 -11l.01 -.013l.018 -.024l.033 -.038l.018 -.022l.009 -.008l.013 -.014l.04 -.036l.028 -.026l.008 -.006a1 1 0 0 1 .402 -.199l.011 -.001l.027 -.005l.074 -.013l.011 -.001l.041 -.002z"/>\
    </svg>
    """

    /// The logo as a template image `side` points square: the bubble, with
    /// the bolt cut out of its body. Drawn at whatever resolution it is shown
    /// at, so the cut stays crisp.
    nonisolated static func logo(side: CGFloat) -> NSImage? {
        guard let bubble = NSImage(data: Data(bubbleSVG.utf8)),
              let bolt = NSImage(data: Data(boltSVG.utf8))
        else { return nil }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            bubble.draw(in: rect)
            // The bolt's 24-unit box, centered on the bubble's body (above
            // its tail): 0.6 of the side.
            let box = rect.width * 0.6
            let center = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.554)
            bolt.draw(
                in: NSRect(x: center.x - box / 2, y: center.y - box / 2, width: box, height: box),
                from: .zero, operation: .destinationOut, fraction: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func settingsClicked() {
        onOpenSettings?()
    }

    @objc private func grantPermissionsClicked() {
        onGrantPermissions?()
    }

    @objc private func checkForUpdatesClicked() {
        Updater.checkForUpdates()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: DictationObserver {
    func dictationStarted() {
        isIdle = false
        setStatus("● recording")
    }

    func dictationLocked() {
        isIdle = false
        setStatus("● recording · press \(hotkey.shortName) to stop")
    }

    func dictationTranscribing() {
        isIdle = false
        setStatus("transcribing…")
    }

    func dictationFinished(_ result: DictationResult) {
        isIdle = true
        setStatus(idleStatus)
    }

    func dictationFailed(_ error: Error) {
        isIdle = true
        setStatus(idleStatus)
    }
}
