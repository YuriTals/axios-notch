import XCTest
@testable import AxiosNotch

final class LimitForecastTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 200_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
    private func limit(_ percent: Double, resetsInMinutes: Double = 240) -> AgentLimit {
        AgentLimit(percent: percent, resetsAt: at(resetsInMinutes))
    }

    /// Feeds readings every 2 minutes and returns the forecast at the end.
    private func run(_ percents: [Double], resetsInMinutes: Double = 240) -> LimitForecast? {
        var forecaster = LimitForecaster()
        var last: AgentLimit?
        for (index, percent) in percents.enumerated() {
            let l = limit(percent, resetsInMinutes: resetsInMinutes)
            forecaster.record(provider: .claude, window: .fiveHour, limit: l, now: at(Double(index) * 2))
            last = l
        }
        return forecaster.forecast(provider: .claude, window: .fiveHour, limit: last!, now: at(Double(percents.count - 1) * 2))
    }

    func testSteadyGrowthProjectsTheTimeToFull() throws {
        // +1 % every 2 minutes from 30 → 40 % over 20 minutes: 60 % left = 120 minutes.
        let forecast = try XCTUnwrap(run([30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]))
        XCTAssertEqual(forecast.secondsToFull / 60, 120, accuracy: 1)
        XCTAssertTrue(forecast.beforeReset)
    }

    func testNotEnoughHistoryStaysQuiet() {
        XCTAssertNil(run([30, 31]))                       // two readings
        XCTAssertNil(run([30, 33, 36]))                   // only 4 minutes
    }

    func testFlatOrFallingUsageHasNoForecast() {
        XCTAssertNil(run([40, 40, 40, 40, 40, 40]))
        XCTAssertNil(run([40, 40, 40, 40, 40, 40, 40, 40]))
        XCTAssertNil(run([42, 41, 41, 40, 40, 40, 40]))
    }

    func testResetsBeforeFullMeansNothingToWarnAbout() throws {
        // Would take 120 minutes but the window resets in 30.
        let forecast = try XCTUnwrap(run([30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40], resetsInMinutes: 30))
        XCTAssertFalse(forecast.beforeReset)
    }

    func testAWindowResetStartsOverTheHistory() {
        var forecaster = LimitForecaster()
        for (index, percent) in [60.0, 70, 80, 90].enumerated() {
            forecaster.record(provider: .claude, window: .fiveHour, limit: limit(percent), now: at(Double(index) * 4))
        }
        // The window rolled over: usage fell and the reset time moved by hours.
        let fresh = AgentLimit(percent: 2, resetsAt: at(240 + 300))
        forecaster.record(provider: .claude, window: .fiveHour, limit: fresh, now: at(16))
        XCTAssertNil(forecaster.forecast(provider: .claude, window: .fiveHour, limit: fresh, now: at(16)))
    }

    func testProvidersAndWindowsAreIndependentAndOldReadingsExpire() {
        var forecaster = LimitForecaster()
        for index in 0..<8 {
            forecaster.record(provider: .claude, window: .fiveHour, limit: limit(30 + Double(index)), now: at(Double(index) * 2))
        }
        let now = at(14)
        XCTAssertNotNil(forecaster.forecast(provider: .claude, window: .fiveHour, limit: limit(37), now: now))
        XCTAssertNil(forecaster.forecast(provider: .codex, window: .fiveHour, limit: limit(37), now: now))
        XCTAssertNil(forecaster.forecast(provider: .claude, window: .weekly, limit: limit(37), now: now))
        // Two hours later the old readings no longer count.
        XCTAssertNil(forecaster.forecast(provider: .claude, window: .fiveHour, limit: limit(37), now: at(14 + 120)))
    }

    func testAlreadyFullHasNoForecast() {
        XCTAssertNil(run([90, 93, 96, 99, 100, 100, 100, 100]))
    }

    func testForecastWording() {
        withLanguage(.pt) {
            XCTAssertEqual(UsageFormat.forecastText(4 * 60), "no ritmo atual, acaba em ~4 min")
            XCTAssertEqual(UsageFormat.forecastText(38 * 60), "no ritmo atual, acaba em ~40 min")
            XCTAssertEqual(UsageFormat.forecastText(80 * 60), "no ritmo atual, acaba em ~1 h 20 min")
            XCTAssertEqual(UsageFormat.forecastText(120 * 60), "no ritmo atual, acaba em ~2 h")
            XCTAssertEqual(UsageFormat.forecastText(10 * 3600), "no ritmo atual, acaba em ~10 h")
            XCTAssertEqual(UsageFormat.forecastText(3 * 86_400), "no ritmo atual, acaba em ~3 dias")
        }
        withLanguage(.en) {
            XCTAssertEqual(UsageFormat.forecastText(38 * 60), "at this pace, runs out in ~40 min")
        }
    }
}

final class ForecastWiringTests: XCTestCase {
    func testReadingsFlowThroughTheStoreIntoAPublishedForecast() {
        let store = AgentUsageStore()
        let start = Date()
        func reading(_ percent: Double, minutes: Double) -> AgentRateLimits {
            AgentRateLimits(
                fiveHour: AgentLimit(percent: percent, resetsAt: start.addingTimeInterval(5 * 3600)),
                weekly: AgentLimit(percent: 5, resetsAt: start.addingTimeInterval(5 * 86_400)),
                planLabel: nil, fetchedAt: start.addingTimeInterval(minutes * 60))
        }

        for step in 0...6 {                                         // every 2 minutes for 12 minutes
            store.process(limits: reading(30 + Double(step) * 2, minutes: Double(step) * 2), for: .claude,
                          now: start.addingTimeInterval(Double(step) * 120))
        }

        let projected = store.forecasts["claude.fiveHour"]
        XCTAssertNotNil(projected)
        XCTAssertEqual((projected?.secondsToFull ?? 0) / 60, 58, accuracy: 4)          // 58 % left at 1 % a minute
        XCTAssertNil(store.forecasts["claude.weekly"])                                 // flat → nothing to say
        XCTAssertNil(store.forecasts["codex.fiveHour"])
    }
}
