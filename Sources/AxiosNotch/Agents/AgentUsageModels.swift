import Foundation

/// A coding CLI whose local history Axios Notch reads. Plan quotas are
/// fetched separately using the CLI's existing sign-in.
enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex
    case antigravity

    /// Keep Antigravity's terminal semantics separate from screen-parsed agents.
    var tool: Tool { self == .antigravity ? .antigravity : .agent(self) }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .antigravity: return "triangle"
        }
    }

    /// The command typed in a normal terminal to start this CLI.
    var launchCommand: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .antigravity: return "agy"
        }
    }
}

/// Disjoint input/cache buckets; `output` includes reasoning, which is
/// retained separately for detail and must never be billed a second time.
struct AgentTokens: Equatable, Codable {
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0
    var reasoning = 0

    /// Everything the model read, cached or not.
    var promptTokens: Int { input + cacheWrite + cacheRead }
    var totalTokens: Int { promptTokens + output }

    static func + (lhs: AgentTokens, rhs: AgentTokens) -> AgentTokens {
        AgentTokens(
            input: lhs.input + rhs.input,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            output: lhs.output + rhs.output,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    static func += (lhs: inout AgentTokens, rhs: AgentTokens) {
        lhs = lhs + rhs
    }

    /// Provider counters can reset; each negative component then contributes zero.
    func subtracting(_ previous: AgentTokens) -> AgentTokens {
        AgentTokens(input: max(0, input - previous.input),
                    cacheWrite: max(0, cacheWrite - previous.cacheWrite),
                    cacheRead: max(0, cacheRead - previous.cacheRead),
                    output: max(0, output - previous.output),
                    reasoning: max(0, reasoning - previous.reasoning))
    }
}

/// One billed response, reduced to just what the dashboard needs: when it
/// happened, what it cost, which model answered, and which project it was
/// run from. Neither prompts nor replies are ever kept.
struct AgentUsageEvent {
    let date: Date
    let model: String?
    let project: String?
    let tokens: AgentTokens
    /// Stable identity of the underlying response (`message.id:requestId`).
    /// Claude Code logs one response several times, once per content block,
    /// so events sharing an id replace each other instead of adding up.
    var id: String? = nil
    /// The log that owns this event, so replacement/removal can invalidate it.
    var source: URL? = nil
}

/// A calendar day, used to bucket events without caring about time zones or
/// time-of-day — two events on the same day always share one `DayKey`.
struct DayKey: Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// A subtotal of priced usage, with missing tariffs kept distinct from zero.
struct AgentCostEstimate: Equatable {
    private(set) var amount: Double?
    private(set) var hasUnpricedUsage = false

    var isPartial: Bool { amount != nil && hasUnpricedUsage }
    var isComplete: Bool { amount != nil && !hasUnpricedUsage }
    var hasUsage: Bool { amount != nil || hasUnpricedUsage }

    mutating func add(_ cost: Double?, tokens: Int) {
        guard tokens > 0 else { return }
        if let cost { amount = (amount ?? 0) + cost }
        else { hasUnpricedUsage = true }
    }

    mutating func merge(_ other: AgentCostEstimate) {
        if let cost = other.amount { amount = (amount ?? 0) + cost }
        hasUnpricedUsage = hasUnpricedUsage || other.hasUnpricedUsage
    }
}

/// One day's worth of spend, for the activity heatmap.
struct AgentDailyActivity: Equatable, Identifiable {
    var id: DayKey { day }
    let day: DayKey
    var costEstimate: AgentCostEstimate
    var cost: Double? { costEstimate.amount }
}

/// A named slice of today's spend — one model or one project.
struct AgentNamedSpend: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let costEstimate: AgentCostEstimate
    var cost: Double? { costEstimate.amount }
}

/// Tokens and estimated spend over some stretch of time. `start`/`end` are
/// only set for the 5-hour session block.
struct AgentUsageWindow: Equatable {
    var tokens = AgentTokens()
    var costEstimate = AgentCostEstimate()
    var cost: Double? { costEstimate.amount }
    var start: Date?
    var end: Date?
}

/// One model's share of recent usage.
struct AgentModelUsage: Equatable, Identifiable {
    var id: String { name }
    /// Raw model id from the logs.
    let name: String
    var tokens: Int
    var costEstimate = AgentCostEstimate()
    var cost: Double? { costEstimate.amount }

    /// Use tokens for every slice when any displayed model lacks a tariff.
    static func usesCost(_ models: [AgentModelUsage]) -> Bool {
        !models.isEmpty && models.allSatisfy { $0.costEstimate.isComplete }
            && models.reduce(0) { $0 + ($1.cost ?? 0) } > 0
    }

    static func ranked(_ models: [AgentModelUsage]) -> [AgentModelUsage] {
        let byCost = usesCost(models)
        return models.sorted {
            let lhs = byCost ? ($0.cost ?? 0) : Double($0.tokens)
            let rhs = byCost ? ($1.cost ?? 0) : Double($1.tokens)
            return lhs == rhs ? $0.name < $1.name : lhs > rhs
        }
    }
}

/// What the notch shows for one provider: today's usage plus the richer
/// breakdown (trend, models, projects, activity history) the dashboard draws.
struct AgentUsageSummary: Equatable {
    let provider: AgentProvider
    var todayTokens = AgentTokens()
    var latestSessionTokens = AgentTokens()
    var todayCostEstimate = AgentCostEstimate()
    var estimatedCostToday: Double? { todayCostEstimate.amount }
    var lastActivity: Date?
    var hasAnySession = false

    /// Index 0...23, one bucket per hour of today, in $.
    var hourlyCostEstimatesToday = Array(repeating: AgentCostEstimate(), count: 24)
    var hourlySpendToday: [Double?] { hourlyCostEstimatesToday.map(\.amount) }
    /// Sorted by cost, highest first.
    var modelSpendToday: [AgentNamedSpend] = []
    /// Sorted by cost, highest first.
    var projectSpendToday: [AgentNamedSpend] = []
    /// Ascending by day, covering the aggregator's retention window.
    var dailyHistory: [AgentDailyActivity] = []
    var historyCostEstimate = AgentCostEstimate()
    var totalCostInHistory: Double? { historyCostEstimate.amount }
    var activeDaysInHistory: Int = 0
    var busiestDay: AgentDailyActivity?

    /// The 5-hour session block that is still running, or nil when the last
    /// block has already ended. Approximates the CLI's rolling 5h window from
    /// local logs; it is not the plan's real quota.
    var fiveHourBlock: AgentUsageWindow?
    /// Rolling last 7 days.
    var week = AgentUsageWindow()
    /// Spend per day for the last 7 days, oldest first, today last.
    var weekDailyCostEstimates = Array(repeating: AgentCostEstimate(), count: 7)
    var weekDailyCost: [Double?] { weekDailyCostEstimates.map(\.amount) }
    /// Last 7 days split by model, biggest first.
    var weekModels: [AgentModelUsage] = []
}
