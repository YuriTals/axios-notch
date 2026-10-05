import XCTest
@testable import AxiosNotch

@MainActor
final class AgentUsageStoreTests: XCTestCase {
    private final class Clock { var date = Date(timeIntervalSinceReferenceDate: 900_000) }
    private func defaults() -> UserDefaults {
        let suite = "axios-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
    private func reading(_ now: Date, percent: Double = 40) -> AgentRateLimits {
        AgentRateLimits(fiveHour: AgentLimit(percent: percent, resetsAt: now.addingTimeInterval(180)),
                        weekly: AgentLimit(percent: 30, resetsAt: now.addingTimeInterval(86400)), fetchedAt: now)
    }

    func testFailuresAreVisibleAndExpiredWindowsDisappearEvenDuringBackoff() async {
        let clock = Clock(), defaults = defaults()
        let initial = reading(clock.date)
        var calls = 0
        let store = AgentUsageStore(defaults: defaults, now: { clock.date }, fetch: { _ in
            calls += 1
            return calls <= AgentProvider.allCases.count ? .init(state: .available(initial), succeeded: true, retryAfter: nil)
                : .init(state: .unavailable("HTTP 429"), succeeded: false, retryAfter: 900)
        })
        await store.refreshLimits()
        clock.date += 120
        await store.refreshLimits()
        XCTAssertEqual(store.limitFailures[.codex], "HTTP 429")
        XCTAssertEqual(store.limits[.codex]?.rateLimits?.fiveHour?.percent, 40)
        clock.date += 61
        await store.refreshLimits()
        XCTAssertNil(store.limits[.codex]?.rateLimits?.fiveHour)
        XCTAssertEqual(store.limits[.codex]?.rateLimits?.weekly?.percent, 30)
        XCTAssertEqual(calls, AgentProvider.allCases.count * 2, "backoff must still prevent requests")
        clock.date += 6 * 3600
        store.expireLimits()
        XCTAssertNil(store.limits[.codex]?.rateLimits)
        XCTAssertEqual(LimitBackoff.load(for: .codex, defaults: defaults).failures, 1)
    }

    func testCacheAndFailuresUseInjectedDefaultsAndClock() async {
        let clock = Clock(), defaults = defaults()
        LimitCache.save(reading(clock.date), for: .claude, defaults: defaults)
        let store = AgentUsageStore(defaults: defaults, now: { clock.date }, fetch: { _ in
            .init(state: .unavailable("HTTP 401"), succeeded: false, retryAfter: nil)
        })
        XCTAssertNotNil(store.limits[.claude]?.rateLimits)
        await store.refreshLimits()
        XCTAssertEqual(store.limitFailures[.claude], "HTTP 401")
        XCTAssertEqual(store.limits[.codex], .unavailable("HTTP 401"))
        clock.date += 181
        store.expireLimits()
        XCTAssertNil(store.limits[.claude]?.rateLimits?.fiveHour)
    }

    func testOverlappingRequestsAndLateCompletionAfterStop() async {
        let clock = Clock(), initial = reading(clock.date)
        var continuations: [CheckedContinuation<RateLimitClient.Result, Never>] = []
        let store = AgentUsageStore(defaults: defaults(), now: { clock.date }, fetch: { _ in
            await withCheckedContinuation { continuations.append($0) }
        })
        let first = Task { await store.refreshLimits() }
        while continuations.count < AgentProvider.allCases.count { await Task.yield() }
        clock.date += 600
        await store.refreshLimits()
        XCTAssertEqual(continuations.count, AgentProvider.allCases.count, "one request per provider, even past the reserve interval")
        store.stop()
        for continuation in continuations { continuation.resume(returning: .init(state: .available(initial), succeeded: true, retryAfter: nil)) }
        await first.value
        XCTAssertEqual(store.limits[.claude], .loading)
        await store.refreshLimits()
        XCTAssertEqual(continuations.count, AgentProvider.allCases.count, "paused refresh is suppressed")
    }

    func testForecastExpiresAndMissingWindowClearsItsHistory() {
        let clock = Clock()
        let store = AgentUsageStore(defaults: defaults(), now: { clock.date }, fetch: { _ in .init(state: .loading, succeeded: false, retryAfter: nil) })
        let reset = clock.date.addingTimeInterval(18000)
        for step in 0...6 {
            let now = clock.date.addingTimeInterval(Double(step) * 120)
            store.process(limits: AgentRateLimits(fiveHour: AgentLimit(percent: 30 + Double(step), resetsAt: reset), fetchedAt: now), for: .claude, now: now)
        }
        XCTAssertNotNil(store.forecasts["claude.fiveHour"])
        store.process(limits: AgentRateLimits(fetchedAt: clock.date), for: .claude, now: clock.date)
        XCTAssertNil(store.forecasts["claude.fiveHour"])
        store.process(limits: AgentRateLimits(fiveHour: AgentLimit(percent: 50, resetsAt: reset), fetchedAt: clock.date), for: .claude, now: clock.date)
        XCTAssertNil(store.forecasts["claude.fiveHour"], "missing window discarded its old samples")
    }

    func testForecastExpiresWhileTheReadingRemainsValid() async {
        let clock = Clock()
        let start = clock.date
        var percent = 30.0
        let store = AgentUsageStore(defaults: defaults(), now: { clock.date }, fetch: { _ in
            .init(state: .available(AgentRateLimits(fiveHour: AgentLimit(percent: percent, resetsAt: start.addingTimeInterval(18000)),
                fetchedAt: clock.date)), succeeded: true, retryAfter: nil)
        })
        for step in 0...2 {
            clock.date = start.addingTimeInterval(Double(step) * 300)
            percent += 5
            await store.refreshLimits()
        }
        XCTAssertNotNil(store.forecasts["claude.fiveHour"])
        clock.date += 241
        store.expireLimits()
        XCTAssertNotNil(store.limits[.claude]?.rateLimits?.fiveHour)
        XCTAssertNil(store.forecasts["claude.fiveHour"])
    }

    func testResumeAndRepeatedStartDoNotDuplicatePolling() async {
        let clock = Clock()
        var calls = 0
        let absentRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AgentUsageStore(defaults: defaults(), now: { clock.date }, fetch: { _ in
            calls += 1
            return .init(state: .unavailable("offline"), succeeded: false, retryAfter: nil)
        }, claudeReader: ClaudeUsageReader(root: absentRoot), codexReader: CodexUsageReader(root: absentRoot), antigravityReader: AntigravityUsageReader(root: absentRoot))
        defer { store.stop() }
        store.stop()
        await store.refreshLimits()
        XCTAssertEqual(calls, 0)
        store.start()
        store.start()
        while calls < AgentProvider.allCases.count { await Task.yield() }
        await store.refreshLimits()
        XCTAssertEqual(calls, AgentProvider.allCases.count)
        store.stop()
        clock.date += 120
        store.start()
        while calls < AgentProvider.allCases.count * 2 { await Task.yield() }
        XCTAssertEqual(calls, AgentProvider.allCases.count * 2)
    }
}
