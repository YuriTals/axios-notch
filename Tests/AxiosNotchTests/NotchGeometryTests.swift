import AppKit
import XCTest
@testable import AxiosNotch

final class NotchGeometryTests: XCTestCase {
    func testReturnsZeroFrameWhenThereIsNoScreenAtAll() {
        let geometry = NotchGeometry.current(for: nil)

        XCTAssertFalse(geometry.hasPhysicalNotch)
        XCTAssertEqual(geometry.frame, .zero)
    }

    func testMainScreenAlwaysProducesAUsableFrame() throws {
        // Whatever this machine's main screen looks like (notch or not),
        // the geometry it produces should always be positive-sized and
        // anchored to the top edge of that screen.
        guard let screen = NSScreen.main else {
            throw XCTSkip("no attached screen to test against")
        }
        let geometry = NotchGeometry.current(for: screen)

        XCTAssertGreaterThan(geometry.frame.width, 0)
        XCTAssertGreaterThan(geometry.frame.height, 0)
        XCTAssertEqual(geometry.frame.maxY, screen.frame.maxY, accuracy: 0.5)
    }
}
