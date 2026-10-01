import Foundation

/// Turns a stream of `AgentUsageEvent`s into the breakdown the dashboard
/// draws: today's hourly/model/project spend, plus a daily history for the
/// activity heatmap. Recomputes everything from the retained events on every
/// `snapshot(now:)` call rather than maintaining running buckets, so a day
/// rollover or a clock change can't leave stale totals behind — the event
/// list is small enough (bounded by `historyWindowDays`) for this to be cheap.
final class AgentUsageAggregator {
    private let calendar: Calendar
    private let historyWindowDays: Int
    private var events: [AgentUsageEvent] = []
    private(set) var lastActivity: Date?

    init(calendar: Calendar = .current, historyWindowDays: Int = 91) {
        self.calendar = calendar
        self.historyWindowDays = historyWindowDays
    }

    private var indexByID: [String: Int] = [:]

    func ingest(_ event: AgentUsageEvent) {
        if let id = event.id {
            if let index = indexByID[id], index < events.count, events[index].id == id {
                events[index] = event
            } else {
                indexByID[id] = events.count
                events.append(event)
            }
        } else {
            events.append(event)
        }
        if lastActivity.map({ event.date > $0 }) ?? true {
            lastActivity = event.date
        }
    }

    /// Drops events older than the retention window. Safe to call often —
    /// cheap once the list is already pruned.
    func prune(now: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -historyWindowDays, to: now) else { return }
        guard events.contains(where: { $0.date < cutoff }) else { return }
        events.removeAll { $0.date < cutoff }
        indexByID = [:]
        for (index, event) in events.enumerated() {
            if let id = event.id { indexByID[id] = index }
        }
    }

    struct Breakdown {
        var todayTokens = AgentTokens()
        var estimatedCostToday: Double?
        var hourlySpendToday: [Double] = Array(repeating: 0, count: 24)
        var modelSpendToday: [AgentNamedSpend] = []
        var projectSpendToday: [AgentNamedSpend] = []
        var dailyHistory: [AgentDailyActivity] = []
        var totalCostInHistory: Double = 0
        var activeDaysInHistory: Int = 0
        var busiestDay: AgentDailyActivity?
        var fiveHourBlock: AgentUsageWindow?
        var week = AgentUsageWindow()
        var weekDailyCost: [Double] = Array(repeating: 0, count: 7)
    }

    static let blockLength: TimeInterval = 5 * 3600

    func snapshot(now: Date) -> Breakdown {
        prune(now: now)

        var dailyCost: [DayKey: Double] = [:]
        var hourlyToday = Array(repeating: 0.0, count: 24)
        var modelToday: [String: Double] = [:]
        var projectToday: [String: Double] = [:]
        var todayTokens = AgentTokens()
        let todayKey = DayKey(date: now, calendar: calendar)

        for event in events {
            let cost = event.model.flatMap { AgentPricing.estimatedCost(model: $0, tokens: event.tokens) } ?? 0
            let key = DayKey(date: event.date, calendar: calendar)
            dailyCost[key, default: 0] += cost

            guard key == todayKey else { continue }
            todayTokens += event.tokens
            let hour = calendar.component(.hour, from: event.date)
            hourlyToday[hour] += cost
            if let model = event.model {
                modelToday[model, default: 0] += cost
            }
            if let project = event.project {
                projectToday[project, default: 0] += cost
            }
        }

        let weekStart = now.addingTimeInterval(-7 * 86_400)
        var week = AgentUsageWindow()
        for event in events where event.date >= weekStart && event.date <= now {
            week.tokens += event.tokens
            week.cost += cost(of: event)
        }
        let weekDaily: [Double] = (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: now) else { return 0 }
            return dailyCost[DayKey(date: day, calendar: calendar)] ?? 0
        }

        let history = dailyCost
            .map { AgentDailyActivity(day: $0.key, cost: $0.value) }
            .sorted { $0.day < $1.day }

        return Breakdown(
            todayTokens: todayTokens,
            estimatedCostToday: dailyCost[todayKey],
            hourlySpendToday: hourlyToday,
            modelSpendToday: modelToday.map { AgentNamedSpend(name: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost },
            projectSpendToday: projectToday.map { AgentNamedSpend(name: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost },
            dailyHistory: history,
            totalCostInHistory: history.reduce(0) { $0 + $1.cost },
            activeDaysInHistory: history.filter { $0.cost > 0 }.count,
            busiestDay: history.max { $0.cost < $1.cost },
            fiveHourBlock: activeBlock(now: now),
            week: week,
            weekDailyCost: weekDaily
        )
    }

    private func cost(of event: AgentUsageEvent) -> Double {
        event.model.flatMap { AgentPricing.estimatedCost(model: $0, tokens: event.tokens) } ?? 0
    }

    /// A block opens at the first event after the previous one ended
    /// (floored to the hour) and lasts five hours. Returns the block only
    /// while `now` is still inside it.
    private func activeBlock(now: Date) -> AgentUsageWindow? {
        var blockStart: Date?
        for event in events.sorted(by: { $0.date < $1.date }) where event.date <= now {
            if let start = blockStart, event.date < start.addingTimeInterval(Self.blockLength) { continue }
            blockStart = calendar.dateInterval(of: .hour, for: event.date)?.start ?? event.date
        }
        guard let start = blockStart else { return nil }
        let end = start.addingTimeInterval(Self.blockLength)
        guard now < end else { return nil }

        var block = AgentUsageWindow(start: start, end: end)
        for event in events where event.date >= start && event.date <= now {
            block.tokens += event.tokens
            block.cost += cost(of: event)
        }
        return block
    }
}
