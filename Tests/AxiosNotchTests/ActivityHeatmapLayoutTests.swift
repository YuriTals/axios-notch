import XCTest
@testable import AxiosNotch

final class ActivityHeatmapLayoutTests: XCTestCase {
    func testProducesThirteenColumnsOfSevenDays() {
        let calendar = Calendar.current
        let now = Date()

        let columns = ActivityHeatmapLayout.columns(history: [], now: now, calendar: calendar, weeks: 13)

        XCTAssertEqual(columns.count, 13)
        XCTAssertTrue(columns.allSatisfy { $0.count == 7 })
    }

    func testPlacesTodaysCostInTheLastColumnsLastRow() {
        let calendar = Calendar.current
        let now = Date()
        let today = AgentDailyActivity(day: DayKey(date: now, calendar: calendar), cost: 42)

        let columns = ActivityHeatmapLayout.columns(history: [today], now: now, calendar: calendar, weeks: 13)

        XCTAssertEqual(columns.last?.last, 42)
    }

    func testDaysWithoutRecordedCostAreZero() {
        let calendar = Calendar.current
        let now = Date()

        let columns = ActivityHeatmapLayout.columns(history: [], now: now, calendar: calendar, weeks: 13)

        XCTAssertTrue(columns.allSatisfy { column in column.allSatisfy { $0 == 0 } })
    }
}
