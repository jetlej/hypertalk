import CoreGraphics
import XCTest
@testable import HypertalkCore

final class CustomHotkeyTests: XCTestCase {
    private let combo = CustomHotkey(keyCode: 49, modifiers: [.option, .control], keyName: "Space")
    private let chord = CustomHotkey(keyCode: nil, modifiers: [.command, .control], keyName: nil)

    func testLabelsListModifiersInMenuOrder() {
        XCTAssertEqual(combo.label, "⌃ ⌥ Space")
        XCTAssertEqual(chord.label, "⌃ ⌘")
    }

    func testAKeyWithModifiersIsACombo() {
        XCTAssertEqual(combo.trigger, .combo(keyCode: 49, modifiers: [.maskControl, .maskAlternate]))
        XCTAssertEqual(chord.trigger, .chord([.maskControl, .maskCommand]))
    }

    func testCustomOverridesTheKeyAndRoundTrips() throws {
        var hotkey = HotkeySettings()
        hotkey.key = .rightOption
        XCTAssertEqual(hotkey.trigger, .key(.rightOption))
        hotkey.custom = combo
        XCTAssertEqual(hotkey.trigger, combo.trigger)
        XCTAssertEqual(hotkey.shortName, "⌃ ⌥ Space")
        let decoded = try JSONDecoder().decode(HotkeySettings.self, from: JSONEncoder().encode(hotkey))
        XCTAssertEqual(decoded, hotkey)
    }

    func testOlderAndBrokenFilesFallBackToTheKey() throws {
        let older = try JSONDecoder().decode(HotkeySettings.self, from: Data(#"{"key":"right-option"}"#.utf8))
        XCTAssertNil(older.custom)
        let broken = try JSONDecoder().decode(HotkeySettings.self, from: Data(#"{"key":"fn","custom":{"modifiers":["hyper"]}}"#.utf8))
        XCTAssertNil(broken.custom)
        XCTAssertEqual(broken.trigger, .key(.fn))
    }

    func testOnboardingSavesTheCustomShortcut() {
        let next = Onboarding.apply(hotkey: .fn, custom: combo, lockMode: .doubleTap, languages: ["en"], preferred: ["en"], to: Settings())
        XCTAssertEqual(next.hotkey.custom, combo)
        let back = Onboarding.apply(hotkey: .rightCommand, lockMode: .doubleTap, languages: ["en"], preferred: ["en"], to: next)
        XCTAssertNil(back.hotkey.custom)
    }

    // MARK: - Chord matching

    private let controlCommand: CGEventFlags = [.maskControl, .maskCommand]

    private func input(_ keycode: Int64, _ flags: CGEventFlags, held: Bool) -> Gesture.Input? {
        HotkeyMonitor.input(keycode: keycode, flags: flags, chord: controlCommand, held: held)
    }

    func testChordIsDownOnceEveryModifierIs() {
        XCTAssertNil(input(59, [.maskControl], held: false))
        XCTAssertEqual(input(55, controlCommand, held: false), .hotkeyDown(othersHeld: false))
    }

    func testChordWithAnExtraModifierIsAnotherChord() {
        XCTAssertEqual(input(55, controlCommand.union(.maskShift), held: false), .hotkeyDown(othersHeld: true))
        XCTAssertEqual(input(56, controlCommand.union(.maskShift), held: true), .otherModifier)
    }

    func testChordIsUpWhenAnyModifierLetsGo() {
        XCTAssertEqual(input(59, [.maskCommand], held: true), .hotkeyUp)
        XCTAssertNil(input(55, controlCommand, held: true))
    }
}
