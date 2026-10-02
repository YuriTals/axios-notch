import XCTest
@testable import AxiosNotch

final class PhraseBookTests: XCTestCase {
    func testThereAreLinesForBothKindsInBothLanguagesAndTheyFitTheBanner() {
        for lang in [Lang.pt, .en] {
            XCTAssertGreaterThanOrEqual(PhraseBook.answer(lang).count, 3)
            XCTAssertGreaterThanOrEqual(PhraseBook.command(lang).count, 2)
            for line in PhraseBook.answer(lang) + PhraseBook.command(lang) { XCTAssertLessThanOrEqual(line.count, 32, line) }
        }
        XCTAssertEqual(PhraseBook.answer(.pt).count, PhraseBook.answer(.en).count)
        XCTAssertTrue(Set(PhraseBook.answer(.pt)).isDisjoint(with: PhraseBook.answer(.en)))
    }

    func testNeverRepeatsTheLastLineWhenThereIsAChoice() {
        for lang in [Lang.pt, .en] {
            for previous in PhraseBook.answer(lang) {
                for index in 0..<(PhraseBook.answer(lang).count - 1) {
                    XCTAssertNotEqual(PhraseBook.pick(forShell: false, avoiding: previous, language: lang, randomIndex: { _ in index }), previous)
                }
            }
        }
    }

    func testShellGetsCommandLines() {
        XCTAssertTrue(PhraseBook.command(.pt).contains(PhraseBook.pick(forShell: true, avoiding: nil, language: .pt)))
        XCTAssertTrue(PhraseBook.command(.en).contains(PhraseBook.pick(forShell: true, avoiding: nil, language: .en)))
    }
}
