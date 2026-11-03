import AppKit
import SwiftUI

/// The onboarding window (#51): one decision per page, the talk key,
/// hands-free, the languages the user speaks, then both permissions, each
/// with its own Allow button, so macOS never asks before the window has said
/// why (`OnboardingView`). Hypertalk.app opens it at
/// launch until the user has been through it once (Get Started or closing
/// it), and afterwards while a grant is missing. "Grant Permissions…" in the
/// menu bar reopens it while one is. One instance, reused.
@MainActor
enum OnboardingWindow {
    /// How often the grants are re-read. Accessibility has no change
    /// notification, so this polls, like `Daemon.startHotkey`.
    private static let pollInterval: TimeInterval = 1

    private static var store: SettingsStore?
    private static var menuBar: MenuBarController?
    private static var window: NSWindow?
    private static var model: OnboardingModel?
    private static var poll: Timer?
    private static let delegate = Delegate()
    /// Called after the window closes, by Get Started or by the person.
    static var onClosed: (() -> Void)?
    /// Whether the window is open.
    static var isShowing: Bool { window != nil }

    /// Opens the window if this is Hypertalk.app and `Onboarding.showsWindow`
    /// says so, and keeps "Grant Permissions…" shown while a grant is
    /// missing. Does nothing in a foreground CLI run.
    static func startIfNeeded(store: SettingsStore, menuBar: MenuBarController) {
        guard AppLaunch.isApp else { return }
        self.store = store
        self.menuBar = menuBar
        menuBar.onGrantPermissions = { show() }
        refresh()
        guard Onboarding.showsWindow(
            isApp: true,
            completed: store.current.onboarding.completed,
            state: PermissionState.current
        ) else { return }
        Log.info("showing the onboarding window")
        // Once the run loop is up, so activation brings the window forward.
        DispatchQueue.main.async { show() }
    }

    static func show() {
        guard let store else { return }
        let window = self.window ?? makeWindow(store: store)
        self.window = window
        startPolling()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // An accessory app's activation can be refused (a login-item launch
        // while the user works elsewhere); the window still comes forward.
        window.orderFrontRegardless()
    }

    private static func makeWindow(store: SettingsStore) -> NSWindow {
        let model = OnboardingModel(settings: store.current)
        model.onGetStarted = { [weak store] in
            guard let store else { return }
            if !model.permissionsOnly {
                store.write(Onboarding.apply(
                    hotkey: model.hotkey,
                    custom: model.custom,
                    lockMode: model.lockMode,
                    languages: model.languages,
                    preferred: model.preferred,
                    to: store.current
                ))
                Log.info("onboarding done: hold \(model.hotkeyName); hands-free \(model.lockMode.rawValue); languages \(model.languages.joined(separator: ", "))")
            }
            self.window?.close()
        }
        self.model = model
        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentView = hosting
        Theme.applyAppearance(to: window)
        window.title = "Welcome to Hypertalk"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.center()
        return window
    }

    /// Polls while the window is open or a grant is missing, so the
    /// checkmarks and the menu item follow System Settings.
    private static func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated { refresh() }
        }
    }

    private static func refresh() {
        let state = PermissionState.current
        model?.update(state)
        menuBar?.setPermissionsMissing(!state.allGranted)
        if state.allGranted && window == nil {
            poll?.invalidate()
            poll = nil
        } else {
            startPolling()
        }
    }

    /// Closing the window by hand counts as done, like Get Started, without
    /// saving the hotkey and languages shown. Quitting Hypertalk with the window
    /// open, or a relaunch after an update, does not.
    fileprivate static func closedByUser() {
        if let store, !store.current.onboarding.completed {
            store.update { $0.onboarding.completed = true }
        }
    }

    fileprivate static func closed() {
        window = nil
        model = nil
        refresh()
        onClosed?()
    }

    private final class Delegate: NSObject, NSWindowDelegate {
        /// Asked only for the close button and ⌘W, not for `close()` from
        /// Get Started or for quitting.
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            MainActor.assumeIsolated { OnboardingWindow.closedByUser() }
            return true
        }

        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated { OnboardingWindow.closed() }
        }
    }
}

/// The onboarding pages, one decision each, in order.
enum OnboardingStep: Int, CaseIterable {
    case hotkey, handsFree, languages, permissions
}

/// The page shown, the choices on the pages, the grants, and the Allow,
/// Back, Continue and Get Started actions.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var state = PermissionState.current
    @Published private(set) var step: OnboardingStep
    @Published var hotkey: HotkeyKey
    @Published var lockMode: LockMode
    /// A recorded shortcut picked in place of `hotkey`.
    @Published var custom: CustomHotkey?
    /// Ticked languages as codes, in the order ticked.
    @Published private(set) var languages: [String]

    let preferred: [String]
    /// Reopened after onboarding only because a grant went missing: just the
    /// permissions page, and Get Started saves nothing.
    let permissionsOnly: Bool
    var onGetStarted: (() -> Void)?

    init(settings: Settings, preferred: [String] = SpokenLanguage.preferredCodes()) {
        hotkey = settings.hotkey.key
        lockMode = settings.hotkey.lockMode
        custom = settings.hotkey.custom
        self.preferred = preferred
        languages = Onboarding.initialLanguages(saved: settings.language.spoken, preferred: preferred)
        permissionsOnly = settings.onboarding.completed
        step = permissionsOnly ? .permissions : .hotkey
    }

    var canContinue: Bool {
        switch step {
        case .hotkey, .handsFree: return true
        case .languages: return !languages.isEmpty
        case .permissions: return state.allGranted
        }
    }

    /// "right ⌥", or a custom shortcut's "⌃ ⌥ Space".
    var hotkeyName: String { custom?.label ?? hotkey.shortName }

    var canGoBack: Bool { !permissionsOnly && step != .hotkey }

    func update(_ now: PermissionState) {
        if now != state { state = now }
    }

    func isTicked(_ code: String) -> Bool { languages.contains(code) }

    func toggle(_ code: String) {
        if let index = languages.firstIndex(of: code) {
            languages.remove(at: index)
        } else {
            languages.append(code)
        }
    }

    /// Runs `kind`'s steps, waiting for the microphone prompt's answer before
    /// re-reading the grants.
    func allow(_ kind: Permissions.Kind) {
        let steps = Permissions.allowSteps(for: kind, in: state)
        if steps == [.requestMicrophone] {
            MicrophoneAccess.requestIfUndetermined { [weak self] in
                MainActor.assumeIsolated { self?.update(PermissionState.current) }
            }
            return
        }
        steps.forEach(Permissions.perform)
    }

    /// The next page, or Get Started on the last.
    func next() {
        guard canContinue else { return }
        if let following = OnboardingStep(rawValue: step.rawValue + 1) {
            step = following
        } else {
            onGetStarted?()
        }
    }

    func back() {
        guard canGoBack, let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}
