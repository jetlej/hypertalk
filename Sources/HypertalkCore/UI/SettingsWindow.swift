import AppKit
import SwiftUI

/// The Settings window (#41), opened from the menu bar's Settings… (⌘,).
/// One instance: opening it again brings the same window to the front, and
/// closing it leaves Hypertalk running.
@MainActor
final class SettingsWindow {
    private let store: SettingsStore
    private let dictionary: DictionaryStore
    private var window: NSWindow?

    init(store: SettingsStore, dictionary: DictionaryStore) {
        self.store = store
        self.dictionary = dictionary
    }

    func show() {
        let window = self.window ?? make()
        self.window = window
        // An accessory app is never active on its own; without this the
        // window opens behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hypertalk Settings"
        // The header inside says it; the title still names the window in
        // Mission Control and the window switcher.
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: SettingsView(store: store, dictionary: dictionary))
        window.isReleasedWhenClosed = false
        Theme.applyAppearance(to: window)
        window.isMovableByWindowBackground = true
        window.center()
        return window
    }
}


/// Every setting on one scrolling page. Controls write straight through to
/// `settings.json` via `SettingsStore`, and a hand edit of the file updates
/// the controls, so the window and the file never disagree. The window holds
/// no state of its own (ADR-002).
///
/// Laid out by hand rather than as a grouped `Form`, whose row boxes can't
/// be removed on macOS: rows sit on the window background and the pills
/// carry the style, as in the onboarding window.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let dictionary: DictionaryStore
    @ObservedObject private var menuBar = MenuBarStatus.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsHeader()
                    .padding(.bottom, 8)
                if menuBar.iconHidden {
                    HiddenIconBanner()
                }
                Divider()
                SettingsGroup("General") {
                    HotkeyRow(store: store)
                    LaunchAtLoginRow()
                }
                Divider()
                OutputSection(store: store)
                Divider()
                TranscriptionSection(store: store)
                Divider()
                DictionarySection(store: store, dictionary: dictionary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
        // Escape and ⌘W close the window: an accessory app has no menu bar
        // of its own to carry Close. Behind the page, so it takes no row.
        .background {
            ZStack {
                Backdrop(glowAt: 0.1)
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 460)
        .frame(minHeight: 420, idealHeight: 680)
        .onExitCommand { NSApp.keyWindow?.performClose(nil) }
    }
}

/// A titled group of rows, such as General.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }
}

/// The Hypertalk logo, with the title and version centered under it.
private struct SettingsHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            LogoBadge(size: 40)
            Wordmark(size: 58)
            MonoLabel("Settings · Version \(AppBundle.version)")
        }
        .frame(maxWidth: .infinity)
    }
}

/// Launch at login through `SMAppService`. Read live, since the user can
/// change it in System Settings while Hypertalk runs; not stored in
/// `settings.json`.
private struct LaunchAtLoginRow: View {
    @State private var isOn = LoginItem.isEnabled

    var body: some View {
        if LoginItem.isAvailable {
            // Outside a Form a toggle is a checkbox; this keeps the switch
            // on the right, like the other controls.
            PillRow("Launch at login") {
                Toggle("Launch at login", isOn: Binding(
                get: { isOn },
                set: { on in
                    do {
                        try LoginItem.setEnabled(on)
                    } catch {
                        Log.warning("couldn't change launch at login: \(error)")
                    }
                    isOn = LoginItem.isEnabled
                }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                isOn = LoginItem.isEnabled
            }
        } else {
            Text("Launch at login is available when Hypertalk runs from Hypertalk.app.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown while macOS keeps the menu-bar icon out of sight: why, and the way
/// back.
private struct HiddenIconBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.2))
            VStack(alignment: .leading, spacing: 6) {
                Text("Your menu bar is full, so macOS hid Hypertalk's icon.")
                    .font(.system(size: 15, weight: .semibold))
                Text("Hold ⌘ and drag other icons off the menu bar to make room. Dictation still works, and opening Hypertalk again from Applications always brings you here.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12)))
    }
}
