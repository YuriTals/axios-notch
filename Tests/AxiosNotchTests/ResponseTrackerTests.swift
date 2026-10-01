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
}
