import SwiftUI

/// The onboarding window's pages, one decision each (`OnboardingStep`): the
/// logo, the question, a line under it, the options drawn so they explain
/// themselves, and Continue with a round Back beside it and the page dots
/// under it. Every page is the same size, so
/// nothing moves between them.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            LogoBadge(size: 36)
            PageTitle(title)
                .padding(.top, 18)
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(model.step)
                .transition(.opacity)

            navigation
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 620, height: 600)
        .background(Backdrop(glowAt: 0.12))
        .animation(.easeOut(duration: 0.2), value: model.step)
    }

    private var key: String { model.hotkeyName }

    private var title: String {
        switch model.step {
        case .hotkey: return "Which key do you hold to talk?"
        case .handsFree: return "Want a hands-free mode?"
        case .languages: return "What languages do you speak?"
        case .permissions: return "Let Hypertalk hear and type"
        }
    }

    private var subtitle: String {
        switch model.step {
        case .hotkey: return "Hold it while you speak. Let go, and your words appear."
        case .handsFree: return "Start with a tap, then talk without holding \(key)."
        case .languages: return "Pick every one you'll talk in. We started with your Mac's."
        case .permissions: return "Audio and text never leave your Mac."
        }
    }

    @ViewBuilder
    private var page: some View {
        switch model.step {
        case .hotkey: HotkeyPage(model: model)
        case .handsFree: HandsFreePage(model: model)
        case .languages: LanguagesPage(model: model)
        case .permissions: PermissionsPage(model: model)
        }
    }

    /// Continue in the middle, Back as a round arrow at the left, and a dot
    /// per page under Continue. Continue is the same width on every page.
    private var navigation: some View {
        VStack(spacing: 16) {
            ZStack {
                Button { model.next() } label: {
                    Text(model.step == .permissions ? "Start Dictating" : "Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 200, height: 30)
                }
                .buttonStyle(.primaryPill)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinue)
                HStack {
                    Button { model.back() } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(OptionStyle(selected: false, capsule: true))
                    .opacity(model.canGoBack ? 1 : 0)
                    .disabled(!model.canGoBack)
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(Color.white.opacity(step == model.step ? 1 : 0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .opacity(model.permissionsOnly ? 0 : 1)
        }
    }
}

/// A picked option is solid white to ice with dark text and a blue glow; the
/// others are outlined on the black.
struct OptionStyle: ButtonStyle {
    let selected: Bool
    var radius: CGFloat = 14
    /// Fully round ends, for one-line buttons.
    var capsule = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = capsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        configuration.label
            .foregroundStyle(selected ? Color.black : Color.white)
            .background {
                if selected {
                    shape.fill(Theme.whiteFill)
                        .shadow(color: Theme.blue.opacity(0.8), radius: 18, y: 4)
                } else {
                    // A light ring behind a dark inside: a stroked capsule
                    // draws stray ticks at its ends.
                    ZStack {
                        shape.fill(Color.white.opacity(0.24))
                        shape.fill(Color(white: configuration.isPressed ? 0.13 : 0.06)).padding(1.5)
                    }
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed && selected ? 0.85 : 1)
    }
}

/// A modifier key's symbol, as printed on the key.
private func glyph(_ key: HotkeyKey) -> String {
    switch key {
    case .fn: return "fn"
    case .leftOption, .rightOption: return "⌥"
    case .leftCommand, .rightCommand: return "⌘"
    case .leftControl, .rightControl: return "⌃"
    case .leftShift, .rightShift: return "⇧"
    }
}

// MARK: - Talk key

/// "Right Option"; fn is "fn / Globe".
private func keyName(_ key: HotkeyKey) -> String {
    key == .fn ? "fn / Globe" : key.displayName.components(separatedBy: " (").first ?? key.displayName
}

/// One large dropdown for the talk key. Closed, it shows the key's icon and
/// name; clicked, a short list opens under it in a panel of its own
/// (`KeyDropdown`): fn and the right-hand keys, More keys for the rest, and
/// Custom shortcut, which closes the list and turns the field into a
/// recorder (`ShortcutRecorder`).
private struct HotkeyPage: View {
    @ObservedObject var model: OnboardingModel
    @State private var dropdown = KeyDropdown()
    @StateObject private var recorder = ShortcutRecorder()
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 14) {
            if recorder.isRecording {
                recorderField
            } else {
                Button(action: open) { field }
                    .buttonStyle(.plain)
                    .background(DropdownAnchor(dropdown: dropdown))
            }
            // Room kept for the line in both states, so the field never moves.
            Text("Press the keys together. Esc cancels.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .opacity(recorder.isRecording ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            dropdown.close()
            recorder.stop()
        }
    }

    private func open() {
        isOpen = true
        dropdown.show(
            selected: model.custom == nil ? model.hotkey : nil,
            custom: model.custom,
            pick: { key in
                model.hotkey = key
                model.custom = nil
            },
            recordCustom: {
                recorder.start { outcome in
                    switch outcome {
                    case .key(let key):
                        model.hotkey = key
                        model.custom = nil
                    case .custom(let shortcut):
                        model.custom = shortcut
                    }
                }
            },
            closed: { isOpen = false }
        )
    }

    private var field: some View {
        HStack(spacing: 14) {
            if let custom = model.custom {
                KeyIcon(symbol: "keyboard", ink: .white, size: 36)
                Text(custom.label)
                    .font(.system(size: 20, weight: .semibold))
            } else {
                KeyIcon(key: model.hotkey, ink: .white, size: 36)
                Text(keyName(model.hotkey))
                    .font(.system(size: 20, weight: .semibold))
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.leading, 12)
        .padding(.trailing, 24)
        .frame(width: KeyList.width, height: 60)
        .background {
            // A light ring behind a dark inside, like `OptionStyle`.
            ZStack {
                Capsule().fill(Color.white.opacity(isOpen ? 0.5 : 0.3))
                Capsule().fill(Color(white: 0.08)).padding(1.5)
            }
        }
        .contentShape(Capsule())
        .animation(.easeOut(duration: 0.15), value: isOpen)
    }

    /// The field while it records: blue-ringed, showing what's held so far.
    private var recorderField: some View {
        HStack(spacing: 14) {
            KeyIcon(symbol: "keyboard", ink: .white, size: 36)
            Text(recorder.prompt)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 24)
        .frame(width: KeyList.width, height: 60)
        .background {
            ZStack {
                Capsule().fill(Theme.blue).shadow(color: Theme.blue, radius: 16)
                Capsule().fill(Color(white: 0.08)).padding(2)
            }
        }
    }
}

/// Hands the field's `NSView` to `KeyDropdown`, which opens under it.
private struct DropdownAnchor: NSViewRepresentable {
    let dropdown: KeyDropdown

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        dropdown.anchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The open key list, in a borderless panel just under the field. It closes
/// on a pick, on Escape, and on a click anywhere else; the arrow keys and
/// Return pick from the keyboard.
@MainActor
final class KeyDropdown {
    weak var anchor: NSView?
    private(set) var panel: NSPanel?
    private var list: KeyListState?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var closed: (() -> Void)?

    /// Room around the list for its glow and shadow.
    private static let margin: CGFloat = 40

    func show(
        selected: HotkeyKey?,
        custom: CustomHotkey?,
        pick: @escaping (HotkeyKey) -> Void,
        recordCustom: @escaping () -> Void,
        closed: @escaping () -> Void
    ) {
        guard panel == nil, let anchor, let parent = anchor.window else { return }
        self.closed = closed
        let list = KeyListState(selected: selected, custom: custom)
        self.list = list
        list.pick = { [weak self] key in
            pick(key)
            self?.close()
        }
        list.recordCustom = { [weak self] in
            self?.close()
            recordCustom()
        }
        // Pinned to the top-left: when More keys opens, the list must not
        // shift under the pointer before the panel grows to fit it.
        let content = NSHostingView(rootView:
            KeyList(state: list)
                .padding(Self.margin)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
        let size = KeyList.size(showingMore: false, margin: Self.margin)
        let field = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        // Under the field, or over it when the screen ends first.
        var origin = NSPoint(x: field.minX - Self.margin, y: field.minY - 8 - size.height + Self.margin)
        if let screen = parent.screen?.visibleFrame, origin.y + Self.margin < screen.minY {
            origin.y = field.maxY + 8 - Self.margin
        }

        let panel = KeyablePanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = content
        panel.alphaValue = 0
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        self.panel = panel

        // More keys opens beside the list: grow the panel to fit, keeping
        // its top-left corner where it is.
        list.sizeChanged = { [weak panel] showingMore in
            guard let panel else { return }
            let size = KeyList.size(showingMore: showingMore, margin: Self.margin)
            panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                switch event.keyCode {
                case 53: self.close()
                case 125: list.move(1)
                case 126: list.move(-1)
                case 124: if list.highlighted == .more { list.showMore(true) }
                case 123: list.showMore(false)
                case 36, 76, 49: list.activateHighlighted()
                default: return event
                }
                return nil
            }
            // A click outside only closes the list, like a menu.
            if event.window !== panel {
                self.close()
                return nil
            }
            return event
        }
        // Switching to another app.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        list = nil
        let parent = panel.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKey()
        closed?()
        closed = nil
    }
}

/// A borderless panel can't become key on its own; the list needs it to
/// light rows under the pointer and take the arrow keys.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A row of the list: a key, More keys, or Custom shortcut.
enum KeyRow: Hashable {
    case key(HotkeyKey)
    case more
    case custom
}

/// What the open list shows: the row under the pointer or the arrow keys,
/// and whether More keys is open.
@MainActor
final class KeyListState: ObservableObject {
    static let mainKeys: [HotkeyKey] = [.fn, .rightOption, .rightCommand, .rightControl, .rightShift]
    static let moreKeys: [HotkeyKey] = [.leftOption, .leftCommand, .leftControl, .leftShift]

    let selected: HotkeyKey?
    let custom: CustomHotkey?
    @Published var highlighted: KeyRow?
    @Published private(set) var showingMore = false

    var pick: (HotkeyKey) -> Void = { _ in }
    var recordCustom: () -> Void = {}
    var sizeChanged: (Bool) -> Void = { _ in }

    init(selected: HotkeyKey?, custom: CustomHotkey?, showingMore: Bool = false) {
        self.selected = selected
        self.custom = custom
        self.showingMore = showingMore
        if let selected {
            highlighted = Self.mainKeys.contains(selected) ? .key(selected) : .more
        } else {
            highlighted = .custom
        }
    }

    /// The rows the arrow keys walk: the list, then More keys' rows when open.
    private var rows: [KeyRow] {
        Self.mainKeys.map(KeyRow.key) + [.more] + (showingMore ? Self.moreKeys.map(KeyRow.key) : []) + [.custom]
    }

    func move(_ step: Int) {
        let rows = rows
        let index = highlighted.flatMap { rows.firstIndex(of: $0) } ?? (step > 0 ? -1 : rows.count)
        highlighted = rows[min(max(index + step, 0), rows.count - 1)]
    }

    func hover(_ row: KeyRow, _ inside: Bool) {
        if inside {
            highlighted = row
            switch row {
            case .more: showMore(true)
            case .key(let key) where Self.moreKeys.contains(key): break
            default: showMore(false)
            }
        } else if highlighted == row {
            highlighted = nil
        }
    }

    func showMore(_ show: Bool) {
        guard showingMore != show else { return }
        // Grow first, so the list has room before it draws the submenu.
        if show { sizeChanged(true) }
        showingMore = show
        if !show { DispatchQueue.main.async { self.sizeChanged(false) } }
    }

    func activate(_ row: KeyRow) {
        switch row {
        case .key(let key): pick(key)
        case .more: showMore(true)
        case .custom: recordCustom()
        }
    }

    func activateHighlighted() {
        if let highlighted { activate(highlighted) }
    }
}

/// The open list: fn and the right-hand keys, More keys with the rest beside
/// it, and Custom shortcut.
private struct KeyList: View {
    static let width: CGFloat = 340
    private static let rowHeight: CGFloat = 44
    private static let spacing: CGFloat = 2

    @ObservedObject var state: KeyListState

    /// The panel's size, measured from a list in that state.
    @MainActor
    static func size(showingMore: Bool, margin: CGFloat) -> NSSize {
        let state = KeyListState(selected: nil, custom: nil, showingMore: showingMore)
        return NSHostingView(rootView: KeyList(state: state).padding(margin)).fittingSize
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            column(width: Self.width) {
                ForEach(KeyListState.mainKeys, id: \.self) { keyRow($0) }
                KeyMenuRow(
                    icon: KeyIcon(symbol: "ellipsis", ink: .white, size: 32),
                    name: "More keys",
                    detail: state.selected.flatMap { KeyListState.moreKeys.contains($0) ? keyName($0) : nil },
                    trailing: "chevron.right",
                    highlighted: state.highlighted == .more || state.showingMore,
                    hover: { state.hover(.more, $0) },
                    action: { state.activate(.more) }
                )
                Divider().overlay(Color.white.opacity(0.12)).padding(.vertical, 4)
                KeyMenuRow(
                    icon: KeyIcon(symbol: "keyboard", ink: .white, size: 32),
                    name: state.custom == nil ? "Custom shortcut…" : "Custom",
                    detail: state.custom?.label,
                    trailing: state.custom != nil ? "checkmark" : nil,
                    highlighted: state.highlighted == .custom,
                    hover: { state.hover(.custom, $0) },
                    action: { state.activate(.custom) }
                )
            }
            if state.showingMore {
                column(width: 250) {
                    ForEach(KeyListState.moreKeys, id: \.self) { keyRow($0) }
                }
                // Level with the More keys row, like a menu's submenu.
                .padding(.top, CGFloat(KeyListState.mainKeys.count) * (Self.rowHeight + Self.spacing))
            }
        }
    }

    private func column<Content: View>(width: CGFloat, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(spacing: Self.spacing) { rows() }
            .padding(8)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5))
            .shadow(color: Theme.blue.opacity(0.55), radius: 26)
            .shadow(color: .black.opacity(0.6), radius: 16, y: 10)
    }

    private func keyRow(_ key: HotkeyKey) -> some View {
        KeyMenuRow(
            icon: KeyIcon(key: key, ink: .white, size: 32),
            name: keyName(key),
            trailing: key == state.selected ? "checkmark" : nil,
            highlighted: state.highlighted == .key(key),
            hover: { state.hover(.key(key), $0) },
            action: { state.activate(.key(key)) }
        )
    }
}

/// One row of the open list: lit under the pointer, with a checkmark or an
/// arrow at the end.
private struct KeyMenuRow: View {
    let icon: KeyIcon
    let name: String
    var detail: String?
    var trailing: String?
    let highlighted: Bool
    let hover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                if let trailing {
                    Image(systemName: trailing)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.trailing, 8)
            .frame(height: Self.height)
            .background {
                if highlighted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
    }

    static let height: CGFloat = 44
}

/// A key drawn as a small keycap: a modifier's symbol (fn, ⌥, ⌘, ⌃ or ⇧),
/// or an SF Symbol for the rows that aren't keys.
private struct KeyIcon: View {
    private let text: String?
    private let symbol: String?
    let ink: Color
    var size: CGFloat = 32

    init(key: HotkeyKey, ink: Color, size: CGFloat = 32) {
        text = glyph(key)
        symbol = nil
        self.ink = ink
        self.size = size
    }

    init(symbol: String, ink: Color, size: CGFloat = 32) {
        text = nil
        self.symbol = symbol
        self.ink = ink
        self.size = size
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        Group {
            if let text {
                Text(text).font(.system(size: size * (text == "fn" ? 0.42 : 0.5), weight: .semibold))
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold))
            }
        }
        .foregroundStyle(ink)
        .frame(width: size, height: size)
        .background(shape.fill(ink.opacity(0.08)))
        .overlay(shape.strokeBorder(ink.opacity(0.5), lineWidth: 1.5))
    }
}

// MARK: - Hands-free

/// A card per `LockMode`, each drawing its taps, and what the picked one
/// does in a line under them.
private struct HandsFreePage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 12) {
                ForEach(LockMode.allCases, id: \.self) { mode in
                    let selected = model.lockMode == mode
                    Button { model.lockMode = mode } label: {
                        VStack(spacing: 18) {
                            TapDiagram(mode: mode, glyph: glyph(model.hotkey), ink: selected ? .black : .white)
                            Text(Self.name(mode))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                    .buttonStyle(OptionStyle(selected: selected, radius: 18))
                }
            }
            Text(Self.explanation(model.lockMode, key: model.hotkeyName))
                .font(.system(size: 17, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(height: 48, alignment: .top)
        }
    }

    private static func name(_ mode: LockMode) -> String {
        switch mode {
        case .doubleTap: return "Double-tap to start"
        case .singleTap: return "Tap once to start"
        case .off: return "No, I'll hold it"
        }
    }

    private static func explanation(_ mode: LockMode, key: String) -> String {
        switch mode {
        case .doubleTap: return "Double-tap \(key), talk, then press it again to finish."
        case .singleTap: return "Tap \(key), talk, then press it again to finish."
        case .off: return "Hypertalk listens only while you hold \(key) down."
        }
    }
}

/// The taps that start a recording, an arrow, and the recording: locked on
/// for the tap modes, held for Hold only.
private struct TapDiagram: View {
    let mode: LockMode
    let glyph: String
    let ink: Color

    var body: some View {
        HStack(spacing: 8) {
            switch mode {
            case .doubleTap:
                HStack(spacing: 4) { keycap(); keycap() }
            case .singleTap:
                keycap()
            case .off:
                keycap(held: true)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ink.opacity(0.5))
            HStack(spacing: 3) {
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .semibold))
                if mode != .off {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(ink)
        }
        .frame(height: 40)
    }

    /// A small key. `held`: drawn wide and pressed down, for a hold.
    private func keycap(held: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Text(glyph)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: held ? 58 : 34, height: 34)
            .background(shape.fill(ink.opacity(held ? 0.18 : 0.06)))
            .overlay(shape.strokeBorder(ink.opacity(0.55), lineWidth: 1.5))
    }
}

// MARK: - Languages

/// The Mac's languages and the common ones as buttons, any other ticked
/// language after them, and More Languages for the rest.
private struct LanguagesPage: View {
    @ObservedObject var model: OnboardingModel
    @State private var showsMore = false

    /// The most buttons that fit, More included.
    private static let fits = 14

    /// The Mac's languages, the common ones, and any other ticked ones, in
    /// place as they are ticked. Unticked common ones go from the end until
    /// all fit.
    private var codes: [String] {
        let menu = Onboarding.languageMenu(preferred: model.preferred)
        let listed = menu.mac + menu.common
        var codes = listed + model.languages.filter { !listed.contains($0) }
        while codes.count > Self.fits - 1,
              let last = codes.lastIndex(where: { menu.common.contains($0) && !model.isTicked($0) }) {
            codes.remove(at: last)
        }
        return codes
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(codes, id: \.self) { code in
                Button { model.toggle(code) } label: {
                    Text(SpokenLanguage.displayName(code))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(OptionStyle(selected: model.isTicked(code), capsule: true))
            }
            Button { showsMore.toggle() } label: {
                Label("More", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(OptionStyle(selected: false, capsule: true))
            .popover(isPresented: $showsMore, arrowEdge: .bottom) {
                LanguageChecklist(ticked: model.languages, toggle: model.toggle)
            }
        }
        .padding(.top, 14)
    }
}

// MARK: - Permissions

/// Microphone and Accessibility side by side, each with its Allow button.
private struct PermissionsPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(spacing: 14) {
            card(
                .microphone,
                symbol: "mic.fill",
                title: "Microphone",
                detail: "To hear you while you talk",
                granted: model.state.microphone == .granted,
                action: model.state.microphone == .denied ? "Open Settings" : "Allow"
            )
            card(
                .accessibility,
                symbol: "keyboard.fill",
                title: "Accessibility",
                detail: "To type your words into any app",
                granted: model.state.accessibility,
                action: "Allow"
            )
        }
    }

    private func card(
        _ kind: Permissions.Kind,
        symbol: String,
        title: String,
        detail: String,
        granted: Bool,
        action: String
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .frame(height: 38)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if granted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Button { model.allow(kind) } label: { Text(action).frame(width: 110) }
                        .buttonStyle(.primaryPill)
                        .controlSize(.large)
                }
            }
            .frame(height: 40)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(shape.fill(Color.white.opacity(0.05)))
        .overlay(shape.strokeBorder(Color.white.opacity(granted ? 0.1 : 0.22), lineWidth: 1.5))
    }
}
