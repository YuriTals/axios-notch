import XCTest
@testable import AxiosNotch

final class LimitAlertTests: XCTestCase {
    private let reset = Date(timeIntervalSinceReferenceDate: 100_000)

    private func limit(_ percent: Double, resets: Date? = nil) -> AgentLimit {
        AgentLimit(percent: percent, resetsAt: resets ?? reset)
    }

    func testFirstReadingNeverAlertsEvenWhenAlreadyHigh() {
        var tracker = LimitAlertTracker()
        XCTAssertNil(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(92)))
        // …and being at 92 already armed both levels: nothing more until it resets.
        XCTAssertNil(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(95)))
    }

    func testAlertsOncePerThresholdAsUsageClimbs() {
        var tracker = LimitAlertTracker()
        XCTAssertNil(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(40)))
        XCTAssertNil(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(79)))

        let at80 = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(81))
        XCTAssertEqual(at80?.kind, .threshold(80))
        XCTAssertEqual(at80?.severity, .warning)
        XCTAssertNil(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(85)))   // same level, no repeat

        let at90 = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(91))
        XCTAssertEqual(at90?.kind, .threshold(90))
        XCTAssertEqual(at90?.severity, .critical)
        XCTAssertNil(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(99)))
    }

    func testJumpingStraightPastBothAlertsAtTheHigherLevel() {
        var tracker = LimitAlertTracker()
        _ = tracker.observe(provider: .codex, window: .weekly, limit: limit(10))
        XCTAssertEqual(tracker.observe(provider: .codex, window: .weekly, limit: limit(93))?.kind, .threshold(90))
    }

    func testReportsWhenAHighWindowStartsOverButStaysQuietIfItWasLow() {
        var tracker = LimitAlertTracker()
        _ = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(70))
        _ = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(88))               // crosses 80
        let next = reset.addingTimeInterval(5 * 3600)
        let alert = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(2, resets: next))
        XCTAssertEqual(alert?.kind, .reset)
        XCTAssertEqual(alert?.message, "Claude: janela de 5h reiniciou!")

        // A window that never got high resets without a word.
        var quiet = LimitAlertTracker()
        _ = quiet.observe(provider: .claude, window: .weekly, limit: limit(30))
        XCTAssertNil(quiet.observe(provider: .claude, window: .weekly, limit: limit(1, resets: next)))
    }

    func testAfterAResetTheThresholdsAreArmedAgain() {
        var tracker = LimitAlertTracker()
        _ = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(85))
        let next = reset.addingTimeInterval(5 * 3600)
        _ = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(5, resets: next))
        XCTAssertEqual(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(82, resets: next))?.kind, .threshold(80))
    }

    func testResetTimeJitterIsNotANewWindow() {
        var tracker = LimitAlertTracker()
        _ = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(60))
        let jittered = limit(85, resets: reset.addingTimeInterval(1.4))
        XCTAssertEqual(tracker.observe(provider: .claude, window: .fiveHour, limit: jittered)?.kind, .threshold(80))
    }

    func testProvidersAndWindowsAreIndependent() {
        var tracker = LimitAlertTracker()
        _ = tracker.observe(provider: .claude, window: .fiveHour, limit: limit(10))
        _ = tracker.observe(provider: .claude, window: .weekly, limit: limit(10))
        _ = tracker.observe(provider: .codex, window: .fiveHour, limit: limit(10))
        XCTAssertNotNil(tracker.observe(provider: .claude, window: .weekly, limit: limit(85)))
        XCTAssertNil(tracker.observe(provider: .claude, window: .fiveHour, limit: limit(20)))
        XCTAssertNil(tracker.observe(provider: .codex, window: .fiveHour, limit: limit(20)))
    }

    func testMessagesReadNaturally() {
        let a = LimitAlert(provider: .claude, window: .fiveHour, kind: .threshold(80), percent: 82.4)
        XCTAssertEqual(a.message, "Claude: 82% da janela de 5h")
        let b = LimitAlert(provider: .codex, window: .weekly, kind: .threshold(90), percent: 91)
        XCTAssertEqual(b.message, "Codex: 91% do limite semanal!")
        XCTAssertEqual(LimitAlert(provider: .codex, window: .weekly, kind: .reset, percent: 0).message, "Codex: limite semanal reiniciou!")
    }
}
