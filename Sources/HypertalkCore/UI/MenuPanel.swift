import AppKit
import SwiftUI

/// What the menu-bar panel shows. `MenuBarController` keeps it current.
@MainActor
final class MenuPanelModel: ObservableObject {
    enum Phase {
        case ready
        case recording
        case transcribing
        /// The hotkey or the model isn't working; the status says why.
        case attention
    }

    @Published var phase: Phase = .ready
    /// One line, such as "Ready · hold fn to dictate".
    @Published var status = ""
    /// A `ModelRegistry` id, with anything after " · " (a load in progress)
    /// shown as is.
    @Published var model = ""
    @Published var showsGrantPermissions = false
    @Published var showsCheckForUpdates = false
}

/// What the panel's rows do.
struct MenuPanelActions {
    var grantPermissions: () -> Void
    var openSettings: () -> Void
    var checkForUpdates: () -> Void
    var quit: () -> Void
}

/// The panel that drops from the menu-bar icon, in place of a system menu.
/// Borderless and above other windows; it closes when it loses focus, on
/// Escape, or when the icon is clicked again.
@MainActor
final class MenuPanel: NSPanel {
    static let width: CGFloat = 290

    init(model: MenuPanelModel, actions: MenuPanelActions) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: MenuPanelView(model: model, actions: actions))
        host.sizingOptions = [.preferredContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    /// Escape closes it, like a menu.
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    /// Opens under `button`, kept on the button's screen.
    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = contentView?.fittingSize ?? frame.size
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
        if let visible = buttonWindow.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        button.highlight(true)
        self.button = button
        // An accessory app is never active on its own; without this the
        // panel can't take the keyboard for ⌘, ⌘Q and Escape.
        NSApp.activate(ignoringOtherApps: true)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        button?.highlight(false)
        orderOut(nil)
    }

    private weak var button: NSStatusBarButton?
}

/// The panel's content: the wordmark, the live status, the model, and the
/// actions.
struct MenuPanelView: View {
    @ObservedObject var model: MenuPanelModel
    let actions: MenuPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LogoBadge(size: 20)
                Wordmark(size: 26)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                StatusDot(phase: model.phase)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.status)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    MonoLabel(modelName)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
            .padding(.horizontal, 10)

            VStack(spacing: 2) {
                if model.showsGrantPermissions {
                    MenuPanelRow(title: "Grant Permissions…", icon: "lock.open", action: actions.grantPermissions)
                }
                MenuPanelRow(title: "Settings…", icon: "slider.horizontal.3", shortcut: "⌘,", action: actions.openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                if model.showsCheckForUpdates {
                    MenuPanelRow(title: "Check for Updates…", icon: "arrow.down.circle", action: actions.checkForUpdates)
                }
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
                MenuPanelRow(title: "Quit Hypertalk", icon: "power", shortcut: "⌘Q", action: actions.quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .frame(width: MenuPanel.width)
        .background(Backdrop(glowAt: 0, intensity: 0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    /// "Parakeet v2 (English)" for "parakeet-tdt-v2", keeping a load in
    /// progress after it.
    private var modelName: String {
        let parts = model.model.components(separatedBy: " · ")
        let name = parts.first.flatMap(ModelRegistry.find)?.displayName ?? parts.first ?? ""
        return ([name] + parts.dropFirst()).joined(separator: " · ")
    }
}

/// Green when ready, red and pulsing while recording, blue while
/// transcribing, amber when something needs attention.
private struct StatusDot: View {
    let phase: MenuPanelModel.Phase
    @State private var pulse = false

    private var color: Color {
        switch phase {
        case .ready: return Color(red: 0.2, green: 0.85, blue: 0.5)
        case .recording: return Color(red: 1, green: 0.27, blue: 0.3)
        case .transcribing: return Theme.ice
        case .attention: return Color(red: 1, green: 0.72, blue: 0.2)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .shadow(color: color.opacity(0.9), radius: 5)
            .scaleEffect(phase == .recording && pulse ? 1.25 : 1)
            .animation(phase == .recording ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = true }
    }
}

/// A row that highlights in blue under the pointer, like a menu item.
private struct MenuPanelRow: View {
    let title: String
    let icon: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(hovering ? .white : .secondary)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(hovering ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Theme.blue.opacity(0.85) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
