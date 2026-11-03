import AppKit

/// Records the talk key from the keyboard: a key with modifiers (⌃⌥Space)
/// as soon as it's pressed, or modifiers alone (⌃⌥) once they're let go.
/// One modifier alone picks that key from the list. Escape or a click
/// anywhere stops it.
///
/// While it records, the hotkey in use is paused (`.shortcutRecording`), so
/// pressing it records it instead of dictating, and a registered combo
/// reaches the recorder.
@MainActor
final class ShortcutRecorder: ObservableObject {
    enum Outcome {
        case key(HotkeyKey)
        case custom(CustomHotkey)
    }

    static let ready = "Press your shortcut"

    @Published private(set) var isRecording = false
    @Published private(set) var prompt = ShortcutRecorder.ready

    private var monitor: Any?
    private var done: ((Outcome) -> Void)?
    /// Modifiers held at once, and the key that started them.
    private var peak: NSEvent.ModifierFlags = []
    private var firstModifierKey: UInt16?

    private static let modifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .function]

    func start(_ done: @escaping (Outcome) -> Void) {
        stop()
        self.done = done
        isRecording = true
        NotificationCenter.default.post(name: .shortcutRecording, object: nil, userInfo: ["active": true])
        prompt = Self.ready
        peak = []
        firstModifierKey = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                self.keyDown(event)
                return nil
            case .flagsChanged:
                self.flagsChanged(event)
                return event
            default:
                self.stop()
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        done = nil
        if isRecording {
            NotificationCenter.default.post(name: .shortcutRecording, object: nil, userInfo: ["active": false])
        }
        isRecording = false
    }

    private func finish(_ outcome: Outcome) {
        let done = done
        stop()
        done?(outcome)
    }

    private func keyDown(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(Self.modifierMask).subtracting(.function)
        if event.keyCode == 53, mods.isEmpty {
            stop()
            return
        }
        let name = Self.keyLabel(event)
        let isFunctionKey = name.count > 1 && name.hasPrefix("F") && Int(name.dropFirst()) != nil
        if mods.isEmpty, !isFunctionKey {
            prompt = "Add ⌃ ⌥ ⇧ or ⌘ to \(name)"
            return
        }
        finish(.custom(CustomHotkey(keyCode: Int(event.keyCode), modifiers: Self.modifiers(mods), keyName: name)))
    }

    private func flagsChanged(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(Self.modifierMask)
        if mods.isEmpty {
            guard !peak.isEmpty else { return }
            let held = peak
            peak = []
            if Self.glyphs(held).count == 1, let key = HotkeyKey.allCases.first(where: { UInt16($0.keycode) == firstModifierKey }) {
                finish(.key(key))
            } else {
                finish(.custom(CustomHotkey(keyCode: nil, modifiers: Self.modifiers(held), keyName: nil)))
            }
            return
        }
        if peak.isEmpty { firstModifierKey = event.keyCode }
        peak.formUnion(mods)
        prompt = Self.glyphs(peak).joined(separator: " ") + " …"
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<CustomHotkey.Modifier> {
        let pairs: [(NSEvent.ModifierFlags, CustomHotkey.Modifier)] = [(.function, .fn), (.control, .control), (.option, .option), (.shift, .shift), (.command, .command)]
        return Set(pairs.filter { flags.contains($0.0) }.map(\.1))
    }

    private static func glyphs(_ mods: NSEvent.ModifierFlags) -> [String] {
        [(NSEvent.ModifierFlags.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { mods.contains($0.0) }
            .map(\.1)
    }

    private static func keyLabel(_ event: NSEvent) -> String {
        let named: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 50: "`",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19",
        ]
        return named[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

extension Notification.Name {
    /// A `ShortcutRecorder` started or stopped; `userInfo["active"]` says which.
    static let shortcutRecording = Notification.Name("HypertalkShortcutRecording")
}
