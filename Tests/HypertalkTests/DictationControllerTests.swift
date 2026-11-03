import XCTest
@testable import HypertalkCore

final class DictationControllerTests: XCTestCase {
    @MainActor func testAnInstantOpenAndCloseIsDiscarded() {
        XCTAssertTrue(DictationController.isTooShort(0.35))
        XCTAssertTrue(DictationController.isTooShort(0.59))
        XCTAssertFalse(DictationController.isTooShort(0.6))
        XCTAssertFalse(DictationController.isTooShort(2))
    }
}
