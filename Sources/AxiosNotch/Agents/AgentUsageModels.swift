import Foundation

/// A coding CLI whose local session logs Axios Notch reads. No API keys, no
/// network calls — everything comes from files the CLI already writes to disk.
enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// The command typed in a normal terminal to start this CLI.
    var launchCommand: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }
}

/// Token counts in a shape both providers' logs can be reduced to.
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

/// One day's worth of spend, for the activity heatmap.
struct AgentDailyActivity: Equatable, Identifiable {
    var id: DayKey { day }
    let day: DayKey
    var cost: Double
}

/// A named slice of today's spend — one model or one project.
struct AgentNamedSpend: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let cost: Double
}

/// Tokens and estimated spend over some stretch of time. `start`/`end` are
/// only set for the 5-hour session block.
struct AgentUsageWindow: Equatable {
    var tokens = AgentTokens()
    var cost: Double = 0
    var start: Date?
    var end: Date?
}

/// One model's share of recent usage.
struct AgentModelUsage: Equatable, Identifiable {
    var id: String { name }
    /// Raw model id from the logs.
    let name: String
    var tokens: Int
    var cost: Double
}

/// What the notch shows for one provider: today's usage plus the richer
/// breakdown (trend, models, projects, activity history) the dashboard draws.
struct AgentUsageSummary: Equatable {
    let provider: AgentProvider
    var todayTokens = AgentTokens()
    var latestSessionTokens = AgentTokens()
    var estimatedCostToday: Double?
    var lastActivity: Date?
    var hasAnySession = false

    /// Index 0...23, one bucket per hour of today, in $.
    var hourlySpendToday: [Double] = Array(repeating: 0, count: 24)
    /// Sorted by cost, highest first.
    var modelSpendToday: [AgentNamedSpend] = []
    /// Sorted by cost, highest first.
    var projectSpendToday: [AgentNamedSpend] = []
    /// Ascending by day, covering the aggregator's retention window.
    var dailyHistory: [AgentDailyActivity] = []
    var totalCostInHistory: Double = 0
    var activeDaysInHistory: Int = 0
    var busiestDay: AgentDailyActivity?

    /// The 5-hour session block that is still running, or nil when the last
    /// block has already ended. Approximates the CLI's rolling 5h window from
    /// local logs; it is not the plan's real quota.
    var fiveHourBlock: AgentUsageWindow?
    /// Rolling last 7 days.
    var week = AgentUsageWindow()
    /// Spend per day for the last 7 days, oldest first, today last.
    var weekDailyCost: [Double] = Array(repeating: 0, count: 7)
    /// Last 7 days split by model, biggest first.
    var weekModels: [AgentModelUsage] = []
}
