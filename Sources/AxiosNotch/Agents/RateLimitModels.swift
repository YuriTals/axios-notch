import Foundation

/// How much of a plan's window is used, as the provider itself reports it.
struct AgentLimit: Equatable {
    /// 0...100 (can exceed 100 briefly when over limit).
    var percent: Double
    var resetsAt: Date?
}

struct AgentRateLimits: Equatable {
    var fiveHour: AgentLimit?
    var weekly: AgentLimit?
    var planLabel: String?
    var fetchedAt: Date
}

/// What the UI knows about a provider's limits right now.
enum LimitState: Equatable {
    case loading
    case available(AgentRateLimits)
    /// Not signed in, token expired, offline… `reason` is shown to the user.
    case unavailable(String)
}

enum RateLimitParser {
    /// `GET api.anthropic.com/api/oauth/usage` →
    /// `{ five_hour: { utilization, resets_at }, seven_day: { … } }`
    static func claude(_ json: Any, plan: String?, now: Date = Date()) -> AgentRateLimits? {
        guard let root = json as? [String: Any] else { return nil }
        func limit(_ key: String) -> AgentLimit? {
            guard let period = root[key] as? [String: Any],
                  let percent = number(period["utilization"]) else { return nil }
            let reset = (period["resets_at"] as? String).flatMap(ClaudeUsageReader.parseTimestamp)
            return AgentLimit(percent: percent, resetsAt: reset)
        }
        let five = limit("five_hour"), week = limit("seven_day")
        guard five != nil || week != nil else { return nil }
        return AgentRateLimits(fiveHour: five, weekly: week, planLabel: plan, fetchedAt: now)
    }

    /// `GET chatgpt.com/backend-api/wham/usage`. The windows can arrive as
    /// `rate_limit.primary_window/secondary_window` or `primary/secondary`;
    /// the shorter window is the 5-hour one, the longer the weekly one.
    static func codex(_ json: Any, now: Date = Date()) -> AgentRateLimits? {
        guard let root = json as? [String: Any] else { return nil }
        var windows: [[String: Any]] = []
        if let nested = root["rate_limit"] as? [String: Any],
           nested["primary_window"] != nil || nested["secondary_window"] != nil {
            windows = [nested["primary_window"], nested["secondary_window"]].compactMap { $0 as? [String: Any] }
        } else if let nested = root["rate_limits"] as? [String: Any] {
            windows = [nested["primary"], nested["secondary"]].compactMap { $0 as? [String: Any] }
        } else {
            windows = [root["primary"], root["secondary"]].compactMap { $0 as? [String: Any] }
        }
        guard !windows.isEmpty else { return nil }

        func minutes(_ w: [String: Any]) -> Double? {
            number(w["window_minutes"]) ?? number(w["windowDurationMins"]) ?? number(w["limit_window_seconds"]).map { $0 / 60 }
        }
        func limit(_ w: [String: Any]) -> AgentLimit? {
            guard let percent = number(w["used_percent"]) ?? number(w["usedPercent"]) else { return nil }
            var reset: Date?
            if let absolute = number(w["reset_at"]) ?? number(w["resets_at"]) ?? number(w["resetsAt"]), absolute > 0 {
                reset = Date(timeIntervalSince1970: absolute < 1e11 ? absolute : absolute / 1000)
            } else if let after = number(w["reset_after_seconds"]) {
                reset = now.addingTimeInterval(after)
            }
            return AgentLimit(percent: percent, resetsAt: reset)
        }

        let sorted = windows.sorted { (minutes($0) ?? 0) < (minutes($1) ?? 0) }
        let short = sorted.first.flatMap(limit)
        let long = sorted.count > 1 ? sorted.last.flatMap(limit) : nil
        guard short != nil || long != nil else { return nil }
        return AgentRateLimits(fiveHour: short, weekly: long, planLabel: root["plan_type"] as? String, fetchedAt: now)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
