import AppKit
import ApplicationServices
import XCTest
@testable import HypertalkCore

final class DeliveryTests: XCTestCase {
    private func element(_ pid: pid_t) -> FocusedElement {
        FocusedElement(AXUIElementCreateApplication(pid))
    }

    private func focus(pid: pid_t? = 100, element: FocusedElement? = nil, secure: Bool = false) -> FocusSnapshot {
        FocusSnapshot(pid: pid, element: element, isSecure: secure)
    }

    func testUnchangedFocusInjects() {
        let start = focus(element: element(1))
        XCTAssertEqual(DeliveryDecision.decide(start: start, now: focus(element: element(1))), .inject)
    }

    func testSecureFieldAtStartOrDeliveryDiscards() {
        XCTAssertEqual(DeliveryDecision.decide(start: focus(secure: true), now: focus()), .discardSecure)
        XCTAssertEqual(DeliveryDecision.decide(start: focus(), now: focus(secure: true)), .discardSecure)
        XCTAssertEqual(DeliveryDecision.decide(start: nil, now: focus(secure: true)), .discardSecure)
    }

    /// Secure wins over drift: a password field never gets the clipboard.
    func testSecureFieldAfterDriftStillDiscards() {
        XCTAssertEqual(DeliveryDecision.decide(start: focus(pid: 1), now: focus(pid: 2, secure: true)), .discardSecure)
    }

    func testAppSwitchCopiesToClipboard() {
        XCTAssertEqual(DeliveryDecision.decide(start: focus(pid: 1), now: focus(pid: 2)), .copyToClipboard)
        XCTAssertEqual(DeliveryDecision.decide(start: focus(pid: 1), now: focus(pid: nil)), .copyToClipboard)
    }

    func testElementChangeInSameAppCopiesToClipboard() {
        let start = focus(element: element(1))
        XCTAssertEqual(DeliveryDecision.decide(start: start, now: focus(element: element(2))), .copyToClipboard)
    }

    /// Electron builds its Accessibility tree lazily, so an element seen at
    /// only one end is not drift.
    func testElementSeenOnlyOnceIsNotDrift() {
        XCTAssertEqual(DeliveryDecision.decide(start: focus(), now: focus(element: element(1))), .inject)
        XCTAssertEqual(DeliveryDecision.decide(start: focus(element: element(1)), now: focus()), .inject)
    }

    func testNoStartSnapshotInjects() {
        XCTAssertEqual(DeliveryDecision.decide(start: nil, now: focus(pid: 7)), .inject)
    }

    func testUserMessagesNeverCarryText() {
        XCTAssertEqual(DeliveryError.secureField.userMessage, "password field, transcript discarded")
        XCTAssertEqual(DeliveryError.focusChanged.userMessage, "focus changed, transcript copied")
    }
}

final class SpacingTests: XCTestCase {
    private func spaced(_ text: String, after before: TextBeforeCursor = .unknown) -> String {
        Spacing.spaced(text, before: before)
    }

    func testTrailingSpaceAlways() {
        XCTAssertEqual(spaced("Hello world."), "Hello world. ")
        XCTAssertEqual(spaced("hello"), "hello ")
        XCTAssertEqual(spaced("Next", after: .start), "Next ")
    }

    func testNoTrailingSpaceAfterWhitespace() {
        XCTAssertEqual(spaced("Hello. "), "Hello. ")
        XCTAssertEqual(spaced("Hello\n"), "Hello\n")
    }

    /// A word typed by hand before the cursor.
    func testLeadingSpaceAfterAWordOrPunctuation() {
        XCTAssertEqual(spaced("world", after: .character("o")), " world ")
        XCTAssertEqual(spaced("apples", after: .character("3")), " apples ")
        XCTAssertEqual(spaced("Next", after: .character(".")), " Next ")
        XCTAssertEqual(spaced("next", after: .character(")")), " next ")
    }

    /// After a dictation the cursor follows its trailing space: no double space.
    func testNoLeadingSpaceAfterWhitespaceTheStartOrUnknown() {
        XCTAssertEqual(spaced("Next", after: .character(" ")), "Next ")
        XCTAssertEqual(spaced("Next", after: .character("\n")), "Next ")
        XCTAssertEqual(spaced("Next", after: .character("\t")), "Next ")
        XCTAssertEqual(spaced("Next", after: .start), "Next ")
        XCTAssertEqual(spaced("Next", after: .unknown), "Next ")
    }

    func testNoLeadingSpaceAfterAnOpener() {
        for opener: Character in ["(", "[", "\"", "“", "¿", "/", "@"] {
            XCTAssertEqual(spaced("next", after: .character(opener)), "next ", "after \(opener)")
        }
    }

    func testNoLeadingSpaceBeforePunctuationThatAttaches() {
        XCTAssertEqual(spaced(", and then", after: .character("o")), ", and then ")
        XCTAssertEqual(spaced("?", after: .character("o")), "? ")
        XCTAssertEqual(spaced(" already", after: .character("o")), " already ")
    }

    func testNoSpacesInChineseOrJapanese() {
        XCTAssertEqual(spaced("你好。", after: .character("。")), "你好。")
        XCTAssertEqual(spaced("こんにちは", after: .character("す")), "こんにちは")
        XCTAssertEqual(spaced("你好", after: .character("a")), "你好")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(spaced("", after: .character("o")), "")
    }
}

final class PasteboardSessionTests: XCTestCase {
    private final class FakePasteboard: PasteboardAccess {
        var writes: [(text: String, markers: [String])] = []

        func write(_ text: String, markers: [String]) {
            writes.append((text, markers))
        }
    }

    func testPasteLeavesTheTranscriptOnTheClipboard() {
        let pasteboard = FakePasteboard()
        var pastes = 0
        let session = PasteboardSession(pasteboard: pasteboard, postPaste: { pastes += 1 })
        session.paste("hello")
        XCTAssertEqual(pastes, 1)
        XCTAssertEqual(pasteboard.writes.map(\.text), ["hello"])
        XCTAssertEqual(pasteboard.writes.first?.markers, ["org.nspasteboard.ConcealedType"])
    }

    func testCopyWritesWithoutPasting() {
        let pasteboard = FakePasteboard()
        var pastes = 0
        let session = PasteboardSession(pasteboard: pasteboard, postPaste: { pastes += 1 })
        session.copy("fallback")
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(pasteboard.writes.map(\.text), ["fallback"])
    }
}

/// A write to a real, privately named `NSPasteboard`; the user's clipboard
/// is not touched.
final class SystemPasteboardTests: XCTestCase {
    func testWriteLeavesTheTextAndMarkers() {
        let named = NSPasteboard(name: NSPasteboard.Name("hypertalk-test-\(UUID().uuidString)"))
        defer { named.releaseGlobally() }
        SystemPasteboard(named).write("transcript", markers: PasteboardSession.concealedMarkers)
        XCTAssertEqual(named.string(forType: .string), "transcript")
        XCTAssertNotNil(named.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")))
    }
}
