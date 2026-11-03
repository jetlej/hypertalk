import AppKit
import XCTest
@testable import HypertalkCore

final class MenuBarVisibilityTests: XCTestCase {
    // A 14-inch MacBook Pro: 1512 pt wide, the notch between 663 and 849.
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
    private let left = NSRect(x: 0, y: 950, width: 663, height: 32)
    private let right = NSRect(x: 849, y: 950, width: 663, height: 32)

    private func visible(atX x: CGFloat, occluded: Bool = false, notch: Bool = true) -> Bool {
        MenuBarController.isVisible(
            icon: NSRect(x: x, y: 950, width: 30, height: 24),
            screen: screen,
            leftOfNotch: notch ? left : nil,
            rightOfNotch: notch ? right : nil,
            occluded: occluded
        )
    }

    func testRightOfTheNotchIsVisible() {
        XCTAssertTrue(visible(atX: 1275))
    }

    func testBehindTheNotchIsHidden() {
        XCTAssertFalse(visible(atX: 740))
    }

    func testPushedOffTheBarIsHidden() {
        XCTAssertFalse(visible(atX: -40))
        XCTAssertFalse(MenuBarController.isVisible(icon: NSRect(x: 100, y: 950, width: 30, height: 24), screen: nil, leftOfNotch: nil, rightOfNotch: nil, occluded: false))
    }

    func testCoveredIsHidden() {
        XCTAssertFalse(visible(atX: 1275, occluded: true))
    }

    func testNoNotchAnywhereOnTheBarIsVisible() {
        XCTAssertTrue(visible(atX: 740, notch: false))
    }

    func testPositionGoesJustLeftOfApplesShownIcons() {
        let controlCenter: [String: Any] = [
            "NSStatusItem Preferred Position Clock": 82,
            "NSStatusItem VisibleCC Clock": 1,
            "NSStatusItem Preferred Position WiFi": 211,
            "NSStatusItem VisibleCC WiFi": 1,
            "NSStatusItem Preferred Position Sound": 386.5,
            "NSStatusItem Visible Sound": 1,
            // Hidden icons keep stale positions; they don't count.
            "NSStatusItem Preferred Position Timer": 422,
            "NSStatusItem Visible Timer": 0,
            "NSStatusItem Preferred Position KeyboardBrightness": 445,
        ]
        XCTAssertEqual(MenuBarController.preferredPosition(controlCenter: controlCenter), 387.5)
    }

    func testNoPositionWithoutControlCenterIcons() {
        XCTAssertNil(MenuBarController.preferredPosition(controlCenter: [:]))
    }
}
