import AppKit
import CoreGraphics
import Foundation

/// How a transcript is inserted at the cursor. Paste is the default.
///
/// Paste works in every app that supports paste, including the terminals and
/// Electron editors that ignore `type-unicode` and drop its text with no
/// error. Either way the transcript is left on the clipboard afterwards.
public enum InjectMode: String, Codable, CaseIterable, Sendable {
    case paste
    case typeUnicode = "type-unicode"
}

/// Inserts text at the current cursor location by synthesizing keyboard
/// events: ⌘V over the clipboard (`.paste`) or Unicode key events
/// (`.typeUnicode`). The transcript stays on the clipboard after either, so
/// one that lands in the wrong place, or nowhere, can still be pasted.
///
/// Every event comes from a private `CGEventSource` with its flags set
/// explicitly. An event with a nil source inherits the modifiers the user is
/// holding, so a held Control or Fn turned typed text into shortcuts.
@MainActor
final class TextInjector {
    /// Where every synthesized event is posted. One constant, so the app
    /// matrix in #38 can switch it in one line if a location fails there.
    ///
    /// `.cgSessionEventTap` enters where hardware events enter the login
    /// session, so the event reaches the focused app exactly as a key press
    /// would. Our own tap is `.listenOnly` and returns every event
    /// unchanged, so it cannot swallow what we post. `.cghidEventTap` posts
    /// below the session, where the window server can merge in the physical
    /// modifier state; `.cgAnnotatedSessionEventTap` skips the session taps
    /// other tools install. Neither has a reason we can verify.
    static let postLocation: CGEventTapLocation = .cgSessionEventTap

    /// Virtual keycode for V on ANSI layouts (kVK_ANSI_V).
    private static let keycodeV: CGKeyCode = 9

    /// `CGEventKeyboardSetUnicodeString` takes about 20 UTF-16 units per event.
    private static let chunkSize = 20

    var mode: InjectMode
    private let clipboard: PasteboardSession

    init(mode: InjectMode, pasteboard: NSPasteboard = .general) {
        self.mode = mode
        self.clipboard = PasteboardSession(pasteboard: SystemPasteboard(pasteboard), postPaste: Self.postCommandV)
    }

    /// Inserts `text` at the cursor and leaves it on the clipboard.
    func inject(_ text: String) {
        guard !text.isEmpty else { return }
        switch mode {
        case .paste:
            clipboard.paste(text)
        case .typeUnicode:
            Self.typeUnicode(text)
            clipboard.copy(text)
        }
    }

    /// Leaves `text` on the clipboard for the user to paste.
    func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        clipboard.copy(text)
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keycodeV, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keycodeV, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: postLocation)
        up.post(tap: postLocation)
    }

    private static func typeUnicode(_ text: String) {
        let source = CGEventSource(stateID: .privateState)
        let utf16 = Array(text.utf16)
        var index = 0
        while index < utf16.count {
            var end = min(index + chunkSize, utf16.count)
            // Keep a surrogate pair in one event.
            if end < utf16.count, UTF16.isLeadSurrogate(utf16[end - 1]) {
                end -= 1
            }
            var chunk = Array(utf16[index..<end])
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return }
            down.flags = []
            up.flags = []
            // Payload on key-down only: some apps insert a key-up payload too,
            // which typed every chunk twice.
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            down.post(tap: postLocation)
            up.post(tap: postLocation)
            index = end
        }
    }
}

// MARK: - Clipboard

/// The pasteboard write paste mode needs. `NSPasteboard` in the app, a fake
/// in tests.
protocol PasteboardAccess: AnyObject {
    /// Replaces the contents with `text`, plus an empty item of each marker type.
    func write(_ text: String, markers: [String])
}

/// Puts every transcript on the clipboard to stay, pasted or not, so a
/// dictation that lands in the wrong place, or nowhere, is never lost.
final class PasteboardSession {
    /// nspasteboard.org marker: clipboard managers keep the item out of
    /// their history.
    static let concealedMarkers = ["org.nspasteboard.ConcealedType"]

    private let pasteboard: PasteboardAccess
    private let postPaste: () -> Void

    init(pasteboard: PasteboardAccess, postPaste: @escaping () -> Void) {
        self.pasteboard = pasteboard
        self.postPaste = postPaste
    }

    /// Puts `text` on the clipboard and pastes it.
    func paste(_ text: String) {
        copy(text)
        postPaste()
    }

    /// Puts `text` on the clipboard.
    func copy(_ text: String) {
        pasteboard.write(text, markers: Self.concealedMarkers)
    }
}

/// `PasteboardAccess` over an `NSPasteboard`.
final class SystemPasteboard: PasteboardAccess {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func write(_ text: String, markers: [String]) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for marker in markers {
            item.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
        }
        pasteboard.writeObjects([item])
    }
}
