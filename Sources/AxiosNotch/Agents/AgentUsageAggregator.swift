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

    func ingest(_ event: AgentUsageEvent) {
        events.append(event)
        if lastActivity.map({ event.date > $0 }) ?? true {
            lastActivity = event.date
        }
    }

    /// Drops events older than the retention window. Safe to call often —
    /// cheap once the list is already pruned.
    func prune(now: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -historyWindowDays, to: now) else { return }
        events.removeAll { $0.date < cutoff }
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
    }

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
            busiestDay: history.max { $0.cost < $1.cost }
        )
    }
}
