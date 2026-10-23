import XCTest
@testable import HypertalkCore

final class CorrectionDiffTests: XCTestCase {
    private func diff(_ before: String, dictated: String, _ after: String) -> [Correction]? {
        let span = VocabularyLearner.locate(dictated, in: before)!
        return CorrectionDiff.corrections(before: Array(before), span: span, after: Array(after))
    }

    func testFindsAReplacedWord() {
        let found = diff("Hi team. Check the ver cell dashboard.", dictated: "Check the ver cell dashboard.",
                         "Hi team. Check the Vercel dashboard.")
        XCTAssertEqual(found, [Correction(heard: "ver cell", corrected: "Vercel")])
    }

    func testTextTypedAfterTheDictationIsNotACorrection() {
        let found = diff("Ask Jordan about it.", dictated: "Ask Jordan about it.", "Ask Jordan about it. Thanks!")
        XCTAssertEqual(found, [])
    }

    func testFixPlusMoreTypingStillFindsTheFix() {
        let found = diff("Ask Jordin about it.", dictated: "Ask Jordin about it.", "Ask Jordan about it. Thanks!")
        XCTAssertEqual(found, [Correction(heard: "Jordin", corrected: "Jordan")])
    }

    func testChangedTextOutsideTheDictationIsNotComparable() {
        XCTAssertNil(diff("Hello. Ask Jordin.", dictated: "Ask Jordin.", "Hi. Ask Jordan."))
    }

    func testClearedFieldIsNotComparable() {
        XCTAssertNil(diff("Ask Jordin.", dictated: "Ask Jordin.", ""))
    }

    func testRewritesAreTooLong() {
        let found = diff("Let's meet tomorrow.", dictated: "Let's meet tomorrow.", "We should probably reconvene sometime next week.")
        XCTAssertEqual(found, [])
    }

    // MARK: - What is learnable

    private func learnable(_ heard: String, _ corrected: String, known: Set<String> = []) -> Bool {
        CorrectionDiff.isLearnable(Correction(heard: heard, corrected: corrected)) { known.contains($0) }
    }

    func testLearnsNamesAndTerms() {
        XCTAssertTrue(learnable("ver cell", "Vercel"))
        XCTAssertTrue(learnable("Versailles", "Vercel"))
        XCTAssertTrue(learnable("Lejeune", "Lejuwaan"))
        XCTAssertTrue(learnable("github", "GitHub", known: ["GitHub"]))
    }

    func testSkipsEverydayWordsCapitalsAndRewrites() {
        XCTAssertFalse(learnable("their", "there", known: ["there"]))
        XCTAssertFalse(learnable("monday", "Monday"))
        XCTAssertFalse(learnable("meeting", "call"))
        XCTAssertFalse(learnable("Sara", "Sarah", known: ["Sarah"]))
    }

    func testSkipsCodePathsAndNumbers() {
        XCTAssertFalse(learnable("example dot com", "example.com"))
        XCTAssertFalse(learnable("user path", "/usr/bin"))
        XCTAssertFalse(learnable("snake case", "snake_case"))
        XCTAssertFalse(learnable("twenty", "2020"))
    }
}
