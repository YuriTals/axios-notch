import XCTest
@testable import AxiosNotch

final class ResponseTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testSilenceModeWorksWhileOutputFlowsThenFinishesAfterQuiet() {
        var tracker = ResponseTracker(mode: .silence)
        tracker.userSubmitted(now: at(0))
        tracker.outputReceived(now: at(0.5))
        XCTAssertTrue(tracker.isWorking)

        tracker.outputReceived(now: at(4))   // spinner still redrawing
        XCTAssertNil(tracker.tick(now: at(6)))
        XCTAssertTrue(tracker.isWorking)

        XCTAssertEqual(tracker.tick(now: at(7.1)), .finished)
        XCTAssertFalse(tracker.isWorking)
        XCTAssertFalse(tracker.needsPolling)
    }

    func testOutputWithoutAnEnterIsIgnored() {
        var tracker = ResponseTracker(mode: .silence)
        tracker.outputReceived(now: at(0))   // e.g. a tip or a cursor redraw
        XCTAssertFalse(tracker.isWorking)
        XCTAssertNil(tracker.tick(now: at(10)))
    }

    func testSilenceModeGivesUpIfNothingEverStarts() {
        var tracker = ResponseTracker(mode: .silence)
        tracker.userSubmitted(now: at(0))
        XCTAssertNil(tracker.tick(now: at(7)))
        XCTAssertFalse(tracker.needsPolling)
    }

    func testForegroundModeFollowsTheForegroundProcess() {
        var tracker = ResponseTracker(mode: .foreground)
        tracker.userSubmitted(now: at(0))
        XCTAssertNil(tracker.tick(now: at(0.4), foregroundBusy: true))
        XCTAssertTrue(tracker.isWorking)

        // A quiet long command: silence must not end it.
        tracker.outputReceived(now: at(0.5))
        XCTAssertNil(tracker.tick(now: at(30), foregroundBusy: true))

        XCTAssertEqual(tracker.tick(now: at(31), foregroundBusy: false), .finished)
    }

    func testForegroundModeIgnoresInstantCommands() {
        var tracker = ResponseTracker(mode: .foreground)
        tracker.userSubmitted(now: at(0))
        XCTAssertNil(tracker.tick(now: at(1.2), foregroundBusy: false))
        XCTAssertFalse(tracker.isWorking)
        XCTAssertFalse(tracker.needsPolling)
    }

    func testMarkerModeIgnoresEnterAndOutputAndFollowsTheMarker() {
        var tracker = ResponseTracker(mode: .marker)
        // Enter on an idle prompt plus constant redraws must not look like work.
        tracker.userSubmitted(now: at(0))
        tracker.outputReceived(now: at(0.1))
        XCTAssertNil(tracker.tick(now: at(10), markerVisible: false))
        XCTAssertFalse(tracker.isWorking)
        XCTAssertTrue(tracker.needsPolling)

        XCTAssertNil(tracker.tick(now: at(11), markerVisible: true))
        XCTAssertTrue(tracker.isWorking)

        // One frame without the marker is a redraw blink, not the end.
        XCTAssertNil(tracker.tick(now: at(11.5), markerVisible: false))
        XCTAssertNil(tracker.tick(now: at(12), markerVisible: true))
        XCTAssertTrue(tracker.isWorking)

        XCTAssertNil(tracker.tick(now: at(20), markerVisible: false))
        XCTAssertEqual(tracker.tick(now: at(20.5), markerVisible: false), .finished)
        XCTAssertFalse(tracker.isWorking)
    }
}
