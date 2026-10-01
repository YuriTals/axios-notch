import XCTest
@testable import AxiosNotch

final class AgentUsageAggregatorTests: XCTestCase {
    func testBucketsTodaysSpendByHourModelAndProject() {
        let calendar = Calendar.current
        let now = Date()
        let thisMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let thisEvening = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)!

        let aggregator = AgentUsageAggregator(calendar: calendar)
        aggregator.ingest(AgentUsageEvent(
            date: thisMorning, model: "claude-sonnet-4", project: "axios-notch",
            tokens: AgentTokens(input: 1_000_000, output: 0)
        ))
        aggregator.ingest(AgentUsageEvent(
            date: thisEvening, model: "claude-opus-4", project: "obsidian-sync",
            tokens: AgentTokens(input: 1_000_000, output: 0)
        ))

        let breakdown = aggregator.snapshot(now: now)

        XCTAssertEqual(breakdown.hourlySpendToday[9], 3, accuracy: 0.001)
        XCTAssertEqual(breakdown.hourlySpendToday[21], 15, accuracy: 0.001)
        XCTAssertEqual(breakdown.modelSpendToday.map(\.name), ["claude-opus-4", "claude-sonnet-4"])
        XCTAssertEqual(Set(breakdown.projectSpendToday.map(\.name)), ["axios-notch", "obsidian-sync"])
        XCTAssertEqual(breakdown.estimatedCostToday ?? 0, 18, accuracy: 0.001)
    }

    func testDailyHistoryExcludesEventsOutsideRetentionWindow() {
        let calendar = Calendar.current
        let now = Date()
        let tooOld = calendar.date(byAdding: .day, value: -200, to: now)!
        let recent = calendar.date(byAdding: .day, value: -5, to: now)!

        let aggregator = AgentUsageAggregator(calendar: calendar, historyWindowDays: 91)
        aggregator.ingest(AgentUsageEvent(date: tooOld, model: "claude-sonnet-4", project: "p", tokens: AgentTokens(input: 1_000_000)))
        aggregator.ingest(AgentUsageEvent(date: recent, model: "claude-sonnet-4", project: "p", tokens: AgentTokens(input: 1_000_000)))

        let breakdown = aggregator.snapshot(now: now)

        XCTAssertEqual(breakdown.dailyHistory.count, 1, "the 200-day-old event should have been pruned")
        XCTAssertEqual(breakdown.activeDaysInHistory, 1)
    }

    func testBusiestDayPicksTheHighestCostDay() {
        let calendar = Calendar.current
        let now = Date()
        let quietDay = calendar.date(byAdding: .day, value: -10, to: now)!
        let busyDay = calendar.date(byAdding: .day, value: -3, to: now)!

        let aggregator = AgentUsageAggregator(calendar: calendar)
        aggregator.ingest(AgentUsageEvent(date: quietDay, model: "claude-sonnet-4", project: "p", tokens: AgentTokens(input: 100_000)))
        aggregator.ingest(AgentUsageEvent(date: busyDay, model: "claude-sonnet-4", project: "p", tokens: AgentTokens(input: 10_000_000)))

        let breakdown = aggregator.snapshot(now: now)

        XCTAssertEqual(breakdown.busiestDay?.day, DayKey(date: busyDay, calendar: calendar))
    }
}
