import Foundation

/// Lays out a daily activity history into columns of 7 (one column per
/// week, oldest first, each column's rows running Sunday...Saturday-ish —
/// really just "7 days in a row" since `AgentDailyActivity` doesn't carry a
/// weekday). Pure data shaping, kept separate from the view so it's easy to
/// unit test without SwiftUI.
enum ActivityHeatmapLayout {
    static func columns(
        history: [AgentDailyActivity],
        now: Date,
        calendar: Calendar,
        weeks: Int = 13
    ) -> [[Double]] {
        let costByDay = Dictionary(uniqueKeysWithValues: history.map { ($0.day, $0.cost) })
        let totalDays = weeks * 7

        var days: [Double] = []
        days.reserveCapacity(totalDays)
        for offset in stride(from: totalDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayKey(date: date, calendar: calendar)
            days.append(costByDay[key] ?? 0)
        }

        var result: [[Double]] = []
        var index = 0
        while index < days.count {
            let end = min(index + 7, days.count)
            result.append(Array(days[index..<end]))
            index = end
        }
        return result
    }
}
