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

    func removeEvents(from source: URL) {
        events.removeAll { $0.source == source }
        rebuildIndex()
    }

    func retainSources(_ sources: Set<URL>) {
        let count = events.count
        events.removeAll { event in event.source.map { !sources.contains($0) } ?? false }
        if events.count != count { rebuildIndex() }
    }

    private func rebuildIndex() {
        indexByID = [:]
        for (index, event) in events.enumerated() {
            if let id = event.id { indexByID[id] = index }
        }
        lastActivity = events.map(\.date).max()
    }

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
        rebuildIndex()
    }

    struct Breakdown {
        var todayTokens = AgentTokens()
        var todayCostEstimate = AgentCostEstimate()
        var estimatedCostToday: Double? { todayCostEstimate.amount }
        var hourlyCostEstimatesToday = Array(repeating: AgentCostEstimate(), count: 24)
        var hourlySpendToday: [Double?] { hourlyCostEstimatesToday.map(\.amount) }
        var modelSpendToday: [AgentNamedSpend] = []
        var projectSpendToday: [AgentNamedSpend] = []
        var dailyHistory: [AgentDailyActivity] = []
        var historyCostEstimate = AgentCostEstimate()
        var totalCostInHistory: Double? { historyCostEstimate.amount }
        var activeDaysInHistory: Int = 0
        var busiestDay: AgentDailyActivity?
        var fiveHourBlock: AgentUsageWindow?
        var week = AgentUsageWindow()
        var weekDailyCostEstimates = Array(repeating: AgentCostEstimate(), count: 7)
        var weekDailyCost: [Double?] { weekDailyCostEstimates.map(\.amount) }
        var weekModels: [AgentModelUsage] = []
    }

    static let blockLength: TimeInterval = 5 * 3600

    func snapshot(now: Date) -> Breakdown {
        prune(now: now)

        var dailyCost: [DayKey: AgentCostEstimate] = [:]
        var hourlyToday = Array(repeating: AgentCostEstimate(), count: 24)
        var modelToday: [String: AgentCostEstimate] = [:]
        var projectToday: [String: AgentCostEstimate] = [:]
        var todayTokens = AgentTokens()
        let todayKey = DayKey(date: now, calendar: calendar)

        for event in events {
            let cost = cost(of: event)
            let tokens = event.tokens.totalTokens
            let key = DayKey(date: event.date, calendar: calendar)
            dailyCost[key, default: AgentCostEstimate()].add(cost, tokens: tokens)

            guard key == todayKey else { continue }
            todayTokens += event.tokens
            let hour = calendar.component(.hour, from: event.date)
            hourlyToday[hour].add(cost, tokens: tokens)
            if let model = event.model {
                modelToday[model, default: AgentCostEstimate()].add(cost, tokens: tokens)
            }
            if let project = event.project {
                projectToday[project, default: AgentCostEstimate()].add(cost, tokens: tokens)
            }
        }

        let weekStart = now.addingTimeInterval(-7 * 86_400)
        var week = AgentUsageWindow()
        for event in events where event.date >= weekStart && event.date <= now {
            week.tokens += event.tokens
            week.costEstimate.add(cost(of: event), tokens: event.tokens.totalTokens)
        }
        var byModel: [String: AgentModelUsage] = [:]
        for event in events where event.date >= weekStart && event.date <= now {
            guard let model = event.model, !model.hasPrefix("<") else { continue }   // skip "<synthetic>"
            var entry = byModel[model] ?? AgentModelUsage(name: model, tokens: 0)
            entry.tokens += event.tokens.totalTokens
            entry.costEstimate.add(cost(of: event), tokens: event.tokens.totalTokens)
            byModel[model] = entry
        }
        let weekModels = AgentModelUsage.ranked(Array(byModel.values))

        let weekDaily: [AgentCostEstimate] = (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: now) else { return AgentCostEstimate() }
            return dailyCost[DayKey(date: day, calendar: calendar)] ?? AgentCostEstimate()
        }

        let history = dailyCost
            .map { AgentDailyActivity(day: $0.key, costEstimate: $0.value) }
            .sorted { $0.day < $1.day }
        var historyCost = AgentCostEstimate()
        for day in history { historyCost.merge(day.costEstimate) }
        func namedSpend(_ costs: [String: AgentCostEstimate]) -> [AgentNamedSpend] {
            costs.map { AgentNamedSpend(name: $0.key, costEstimate: $0.value) }.sorted {
                let lhs = $0.cost ?? 0, rhs = $1.cost ?? 0
                return lhs == rhs ? $0.name < $1.name : lhs > rhs
            }
        }

        return Breakdown(
            todayTokens: todayTokens,
            todayCostEstimate: dailyCost[todayKey] ?? AgentCostEstimate(),
            hourlyCostEstimatesToday: hourlyToday,
            modelSpendToday: namedSpend(modelToday),
            projectSpendToday: namedSpend(projectToday),
            dailyHistory: history,
            historyCostEstimate: historyCost,
            activeDaysInHistory: history.filter { $0.costEstimate.hasUsage }.count,
            busiestDay: historyCost.isComplete ? history.max { ($0.cost ?? 0) < ($1.cost ?? 0) } : nil,
            fiveHourBlock: activeBlock(now: now),
            week: week,
            weekDailyCostEstimates: weekDaily,
            weekModels: weekModels
        )
    }

    private func cost(of event: AgentUsageEvent) -> Double? {
        event.model.flatMap { AgentPricing.estimatedCost(model: $0, tokens: event.tokens) }
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
            block.costEstimate.add(cost(of: event), tokens: event.tokens.totalTokens)
        }
        return block
    }
}
