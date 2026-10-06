import XCTest
@testable import AxiosNotch

/// Antigravity reports independent quotas per model family. Forecasts, alerts and the
/// panel must treat each one on its own and never sum them.
@MainActor
final class QuotaGroupTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 300_000)

    private func group(_ id: String, _ label: String, five: Double?, week: Double?, at now: Date) -> AgentQuotaGroup {
        AgentQuotaGroup(id: id, label: label,
                        fiveHour: five.map { AgentLimit(percent: $0, resetsAt: now.addingTimeInterval(5 * 3600)) },
                        weekly: week.map { AgentLimit(percent: $0, resetsAt: now.addingTimeInterval(5 * 86_400)) })
    }

    private func reading(gemini: Double, thirdParty: Double, at now: Date) -> AgentRateLimits {
        AgentRateLimits(quotaGroups: [
            group("gemini", "Gemini Models", five: gemini, week: 5, at: start),
            group("3p", "Claude and GPT models", five: thirdParty, week: 5, at: start),
        ], fetchedAt: now)
    }

    // MARK: Forecaster

    func testForecastsAreKeptPerGroup() {
        var forecaster = LimitForecaster()
        let reset = start.addingTimeInterval(5 * 3600)
        for step in 0...6 {
            let now = start.addingTimeInterval(Double(step) * 120)
            forecaster.record(provider: .antigravity, window: .fiveHour, group: "gemini",
                              limit: AgentLimit(percent: 20 + Double(step) * 2, resetsAt: reset), now: now)
            forecaster.record(provider: .antigravity, window: .fiveHour, group: "3p",
                              limit: AgentLimit(percent: 10, resetsAt: reset), now: now)
        }
        let end = start.addingTimeInterval(12 * 60)
        XCTAssertNotNil(forecaster.forecast(provider: .antigravity, window: .fiveHour, group: "gemini",
                                            limit: AgentLimit(percent: 32, resetsAt: reset), now: end))
        XCTAssertNil(forecaster.forecast(provider: .antigravity, window: .fiveHour, group: "3p",
                                         limit: AgentLimit(percent: 10, resetsAt: reset), now: end), "a flat group has no forecast")
        XCTAssertNil(forecaster.forecast(provider: .antigravity, window: .fiveHour, group: nil,
                                         limit: AgentLimit(percent: 32, resetsAt: reset), now: end), "ungrouped history is separate")
        forecaster.forget(provider: .antigravity, window: .fiveHour)
        XCTAssertNil(forecaster.forecast(provider: .antigravity, window: .fiveHour, group: "gemini",
                                         limit: AgentLimit(percent: 32, resetsAt: reset), now: end), "forget clears every group")
    }

    // MARK: Alerts

    func testAlertsAreIndependentPerGroupAndNameTheGroup() {
        var tracker = LimitAlertTracker()
        let reset = start.addingTimeInterval(3600)
        func limit(_ percent: Double) -> AgentLimit { AgentLimit(percent: percent, resetsAt: reset) }
        XCTAssertNil(tracker.observe(provider: .antigravity, window: .fiveHour, group: "gemini", groupLabel: "Gemini Models", limit: limit(40)))
        XCTAssertNil(tracker.observe(provider: .antigravity, window: .fiveHour, group: "3p", groupLabel: "Claude and GPT models", limit: limit(85)))
        let alert = tracker.observe(provider: .antigravity, window: .fiveHour, group: "gemini", groupLabel: "Gemini Models", limit: limit(82))
        XCTAssertEqual(alert?.kind, .threshold(80))
        withLanguage(.en) { XCTAssertEqual(alert?.message, "Antigravity · Gemini Models: 82% of the 5h window") }
        XCTAssertNil(tracker.observe(provider: .antigravity, window: .fiveHour, group: "3p", groupLabel: "Claude and GPT models", limit: limit(86)),
                     "the other family was already past 80 when first seen")
    }

    // MARK: Store

    func testStoreForecastsTheMostUsedFamilyAndAlertsEachOne() {
        let store = AgentUsageStore(defaults: UserDefaults(suiteName: "axios-quota-\(UUID().uuidString)")!)
        var alerts: [LimitAlert] = []
        let sink = store.alerts.sink { alerts.append($0) }
        defer { sink.cancel() }

        for step in 0...6 {
            let now = start.addingTimeInterval(Double(step) * 120)
            // Gemini climbs 2 points per reading; the other family stays low.
            store.process(limits: reading(gemini: 70 + Double(step) * 2, thirdParty: 12, at: now), for: .antigravity, now: now)
        }
        XCTAssertNotNil(store.forecasts["antigravity.fiveHour"], "the card shows the most used family, which is climbing")
        XCTAssertNil(store.forecasts["antigravity.weekly"], "the weekly quotas are flat")
        XCTAssertTrue(alerts.contains { $0.group == "Gemini Models" && $0.kind == .threshold(80) })
        XCTAssertFalse(alerts.contains { $0.group == "Claude and GPT models" })

        // Quotas that disappear take their history with them.
        let later = start.addingTimeInterval(3600)
        store.process(limits: AgentRateLimits(quotaGroups: [], fetchedAt: later), for: .antigravity, now: later)
        XCTAssertNil(store.forecasts["antigravity.fiveHour"])
    }

    func testClaudeAndCodexKeepTheirSingleLimitBehaviour() {
        let store = AgentUsageStore(defaults: UserDefaults(suiteName: "axios-quota-\(UUID().uuidString)")!)
        var alerts: [LimitAlert] = []
        let sink = store.alerts.sink { alerts.append($0) }
        defer { sink.cancel() }
        for (step, percent) in [70.0, 75, 81].enumerated() {
            let now = start.addingTimeInterval(Double(step) * 120)
            store.process(limits: AgentRateLimits(fiveHour: AgentLimit(percent: percent, resetsAt: now.addingTimeInterval(3600)),
                                                  fetchedAt: now), for: .claude, now: now)
        }
        XCTAssertEqual(alerts.count, 1)
        XCTAssertNil(alerts.first?.group)
        withLanguage(.en) { XCTAssertEqual(alerts.first?.message, "Claude: 81% of the 5h window") }
    }

    // MARK: Panel text

    func testQuotaSummaryText() {
        withLanguage(.pt) {
            XCTAssertEqual(UsageFormat.quotaSummary(fiveHour: 0, weekly: 0.78), "5h 0% · sem. 1%")
            XCTAssertEqual(UsageFormat.quotaSummary(fiveHour: nil, weekly: 42), "5h — · sem. 42%")
        }
        withLanguage(.en) { XCTAssertEqual(UsageFormat.quotaSummary(fiveHour: 12, weekly: nil), "5h 12% · wk —") }
    }
}
