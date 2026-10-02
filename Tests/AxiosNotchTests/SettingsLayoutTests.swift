import XCTest
@testable import AxiosNotch

final class SettingsLayoutTests: XCTestCase {
    private let page = CGSize(width: 440, height: SettingsLayout.gridHeight)
    private let h = SettingsLayout.cardHeight
    private let gap = SettingsLayout.spacing

    func testFourBlocksFormATwoByTwoGridFillingThePage() {
        let frames = CardGridLayout.frames(count: 4, in: page)
        let w = (page.width - gap) / 2
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 0, width: w, height: h))
        XCTAssertEqual(frames[1], CGRect(x: w + gap, y: 0, width: w, height: h))
        XCTAssertEqual(frames[2], CGRect(x: 0, y: h + gap, width: w, height: h))
        XCTAssertEqual(frames[3], CGRect(x: w + gap, y: h + gap, width: w, height: h))
        XCTAssertEqual(frames[3].maxY, page.height, accuracy: 0.001)
    }

    func testASingleBlockIsCentredBothWays() {
        let frame = CardGridLayout.frames(count: 1, in: page)[0]
        XCTAssertEqual(frame.midX, page.width / 2, accuracy: 0.001)
        XCTAssertEqual(frame.midY, page.height / 2, accuracy: 0.001)
        XCTAssertEqual(frame.width, (page.width - gap) / 2, accuracy: 0.001)     // same size as in a grid
    }

    func testALoneLastBlockIsCentredUnderTheOthers() {
        let frames = CardGridLayout.frames(count: 3, in: page)
        XCTAssertEqual(frames[2].midX, page.width / 2, accuracy: 0.001)
        XCTAssertEqual(frames[2].minY, frames[0].maxY + gap, accuracy: 0.001)
        XCTAssertEqual(frames[0].minY, frames[1].minY)
    }

    func testTwoBlocksShareARowCentredVertically() {
        let frames = CardGridLayout.frames(count: 2, in: page)
        XCTAssertEqual(frames[0].minY, frames[1].minY)
        XCTAssertEqual(frames[0].midY, page.height / 2, accuracy: 0.001)
        XCTAssertLessThan(frames[0].maxX, frames[1].minX)
    }

    func testNothingToLayOut() {
        XCTAssertTrue(CardGridLayout.frames(count: 0, in: page).isEmpty)
    }

    func testSettingsPages() {
        XCTAssertEqual(SettingsPage.allCases, [.general, .appearance])
        XCTAssertEqual(SettingsLayout.gridHeight, SettingsLayout.cardHeight * 2 + SettingsLayout.spacing)
        XCTAssertGreaterThan(SettingsLayout.pageHeight, SettingsLayout.gridHeight)       // room at the seam
    }
}
