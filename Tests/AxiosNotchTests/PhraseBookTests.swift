import XCTest
@testable import AxiosNotch

final class PhraseBookTests: XCTestCase {
    func testThereAreLinesForBothKindsAndTheyAreShortEnoughForTheBanner() {
        XCTAssertGreaterThanOrEqual(PhraseBook.answer.count, 3)
        XCTAssertGreaterThanOrEqual(PhraseBook.command.count, 2)
        for line in PhraseBook.answer + PhraseBook.command { XCTAssertLessThanOrEqual(line.count, 32, line) }
    }

    func testNeverRepeatsTheLastLineWhenThereIsAChoice() {
        for previous in PhraseBook.answer {
            for index in 0..<(PhraseBook.answer.count - 1) {
                XCTAssertNotEqual(PhraseBook.pick(forShell: false, avoiding: previous, randomIndex: { _ in index }), previous)
            }
        }
    }

    func testShellGetsCommandLines() {
        let line = PhraseBook.pick(forShell: true, avoiding: nil)
        XCTAssertTrue(PhraseBook.command.contains(line))
    }
}
