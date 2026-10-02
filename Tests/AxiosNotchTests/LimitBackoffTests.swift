import XCTest
@testable import AxiosNotch

final class LimitBackoffTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)

    func testRespectsRetryAfterWithinBounds() {
        var backoff = LimitBackoff()
        backoff.failed(now: t0, retryAfter: 120)
        XCTAssertFalse(backoff.canFetch(now: t0.addingTimeInterval(119)))
        XCTAssertTrue(backoff.canFetch(now: t0.addingTimeInterval(121)))

        var tiny = LimitBackoff()
        tiny.failed(now: t0, retryAfter: 1)                          // never hammer: at least 30 s
        XCTAssertFalse(tiny.canFetch(now: t0.addingTimeInterval(29)))
    }

    func testWithoutRetryAfterItBacksOffExponentiallyAndCaps() {
        var backoff = LimitBackoff()
        var delays: [TimeInterval] = []
        var now = t0
        for _ in 0..<7 {
            backoff.failed(now: now, retryAfter: nil)
            delays.append(backoff.nextAllowed.timeIntervalSince(now))
            now = backoff.nextAllowed
        }
        XCTAssertEqual(delays, [60, 120, 240, 480, 900, 900, 900])
    }

    func testSuccessClearsTheBackoffAndReserveKeepsTheFailureCount() {
        var backoff = LimitBackoff()
        backoff.failed(now: t0, retryAfter: nil)
        backoff.failed(now: t0, retryAfter: nil)
        backoff.reserve(now: t0, for: 120)
        XCTAssertEqual(backoff.failures, 2)

        backoff.succeeded(now: t0, interval: 120)
        XCTAssertEqual(backoff.failures, 0)
    }

    func testCacheKeepsLiveWindowsAndDropsFinishedOnes() {
        let suite = "axios-limits-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let limits = AgentRateLimits(
            fiveHour: AgentLimit(percent: 37, resetsAt: now.addingTimeInterval(-60)),     // already reset
            weekly: AgentLimit(percent: 47, resetsAt: now.addingTimeInterval(3600)),
            modelLimits: [AgentModelLimit(label: "Opus", limit: AgentLimit(percent: 10, resetsAt: now.addingTimeInterval(-5)))],
            planLabel: "pro", fetchedAt: now.addingTimeInterval(-600)
        )
        LimitCache.save(limits, for: .claude, defaults: defaults)

        let loaded = LimitCache.load(for: .claude, now: now, defaults: defaults)
        XCTAssertNil(loaded?.fiveHour)
        XCTAssertEqual(loaded?.weekly?.percent, 47)
        XCTAssertEqual(loaded?.modelLimits, [])
        XCTAssertNil(LimitCache.load(for: .codex, now: now, defaults: defaults))

        // Too old to trust.
        XCTAssertNil(LimitCache.load(for: .claude, now: now.addingTimeInterval(7 * 3600), defaults: defaults))
    }

    func testAgeSuffixAppearsOnlyWhenStale() {
        withLanguage(.pt) {
            let now = Date()
            XCTAssertEqual(UsageFormat.ageSuffix(since: now.addingTimeInterval(-60), now: now), "")
            XCTAssertEqual(UsageFormat.ageSuffix(since: now.addingTimeInterval(-12 * 60), now: now), " · há 12 min")
            XCTAssertEqual(UsageFormat.ageSuffix(since: now.addingTimeInterval(-3 * 3600), now: now), " · há 3 h")
        }
    }
}

final class LimitBackoffPersistenceTests: XCTestCase {
    func testBackoffSurvivesARestart() {
        let suite = "axios-backoff-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()

        var backoff = LimitBackoff()
        backoff.failed(now: now, retryAfter: 600)
        backoff.save(for: .claude, defaults: defaults)

        let reopened = LimitBackoff.load(for: .claude, defaults: defaults)
        XCTAssertFalse(reopened.canFetch(now: now.addingTimeInterval(300)))
        XCTAssertTrue(reopened.canFetch(now: now.addingTimeInterval(601)))
        XCTAssertTrue(LimitBackoff.load(for: .codex, defaults: defaults).canFetch(now: now))
    }
}
