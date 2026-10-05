import Foundation
import CoreFoundation

/// How much of a plan's window is used, as the provider itself reports it.
struct AgentLimit: Equatable, Codable {
    /// 0...100 (can exceed 100 briefly when over limit).
    var percent: Double
    var resetsAt: Date?
}

/// A weekly cap that applies to one model or product (Opus, Sonnet, …).
struct AgentModelLimit: Equatable, Identifiable, Codable {
    var id: String { label }
    let label: String
    var limit: AgentLimit
}

/// Antigravity families have independent quotas; never sum or relabel them.
struct AgentQuotaGroup: Equatable, Identifiable, Codable {
    let id: String
    let label: String
    var fiveHour: AgentLimit?
    var weekly: AgentLimit?

}

struct AgentRateLimits: Equatable, Codable {
    var fiveHour: AgentLimit?
    var weekly: AgentLimit?
    /// Only the caps the provider reports and that have been touched.
    var modelLimits: [AgentModelLimit] = []
    var planLabel: String?
    /// Optional for compatibility with cached Claude/Codex readings.
    var quotaGroups: [AgentQuotaGroup]? = nil
    var fetchedAt: Date

    func valid(at now: Date, maxAge: TimeInterval = 6 * 3600) -> AgentRateLimits? {
        guard now.timeIntervalSince(fetchedAt) >= 0, now.timeIntervalSince(fetchedAt) < maxAge else { return nil }
        func live(_ value: AgentLimit?) -> AgentLimit? {
            guard let value, value.resetsAt.map({ $0 > now }) ?? true else { return nil }
            return value
        }
        var copy = self
        copy.fiveHour = live(fiveHour)
        copy.weekly = live(weekly)
        copy.modelLimits = modelLimits.compactMap { entry in live(entry.limit).map { AgentModelLimit(label: entry.label, limit: $0) } }
        copy.quotaGroups = quotaGroups?.compactMap { group in
            let five = live(group.fiveHour), week = live(group.weekly)
            guard five != nil || week != nil else { return nil }
            return AgentQuotaGroup(id: group.id, label: group.label, fiveHour: five, weekly: week)
        }
        return copy.fiveHour == nil && copy.weekly == nil && copy.modelLimits.isEmpty && (copy.quotaGroups?.isEmpty ?? true) ? nil : copy
    }

    /// Account overview: the most consumed real bucket in each window.
    /// Independent buckets must never be added or averaged into a fake quota.
    func mostUsedLimit(in window: LimitWindow) -> AgentLimit? {
        let direct = window == .fiveHour ? fiveHour : weekly
        return direct ?? quotaGroups?.compactMap { window == .fiveHour ? $0.fiveHour : $0.weekly }
            .max(by: { $0.percent < $1.percent })
    }

    var pickerLimit: AgentLimit? { mostUsedLimit(in: .fiveHour) }
}

/// What the UI knows about a provider's limits right now.
enum LimitState: Equatable {
    case loading
    case available(AgentRateLimits)
    /// Not signed in, token expired, offline… `reason` is shown to the user.
    case unavailable(String)
}

enum RateLimitParser {
    /// Read-only quota summary used by `agy /usage`. No assumed window duration.
    static func antigravity(_ json: Any, now: Date = Date()) -> AgentRateLimits? {
        guard let root = json as? [String: Any] else { return nil }
        let rawGroups = root["groups"] as? [[String: Any]] ?? []
        let groups = rawGroups.compactMap { group -> AgentQuotaGroup? in
            guard let label = group["displayName"] as? String,
                  let buckets = group["buckets"] as? [[String: Any]] else { return nil }
            func limit(_ window: String) -> AgentLimit? {
                guard let bucket = buckets.first(where: { $0["window"] as? String == window && $0["disabled"] as? Bool != true }),
                      let value = bucket["remainingFraction"] as? NSNumber,
                      CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
                let remaining = value.doubleValue
                guard remaining.isFinite,
                      (0...1).contains(remaining),
                      let reset = (bucket["resetTime"] as? String).flatMap(ClaudeUsageReader.parseTimestamp), reset > now else { return nil }
                return AgentLimit(percent: (1 - remaining) * 100, resetsAt: reset)
            }
            let five = limit("5h"), week = limit("weekly")
            guard five != nil || week != nil else { return nil }
            // Bucket IDs identify the family even when its display label changes.
            let ids = buckets.compactMap { $0["bucketId"] as? String }.sorted().joined(separator: "|")
            return AgentQuotaGroup(id: ids.isEmpty ? label : ids, label: label, fiveHour: five, weekly: week)
        }
        guard !groups.isEmpty else { return nil }
        return AgentRateLimits(quotaGroups: groups, fetchedAt: now)
    }
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
        let perModel: [(key: String, label: String)] = [
            ("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet"),
            ("seven_day_omelette", "Fable"), ("seven_day_cowork", "Cowork"),
        ]
        let modelLimits = perModel.compactMap { entry -> AgentModelLimit? in
            guard let found = limit(entry.key), found.percent > 0 else { return nil }
            return AgentModelLimit(label: entry.label, limit: found)
        }
        return AgentRateLimits(fiveHour: five, weekly: week, modelLimits: modelLimits, planLabel: plan, fetchedAt: now)
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

        // A single weekly window is still weekly. Unknown durations must not
        // acquire a misleading label from their position in the response.
        let short = windows.first(where: { minutes($0) == 300 }).flatMap(limit)
        let long = windows.first(where: { minutes($0) == 10080 }).flatMap(limit)
        guard short != nil || long != nil else { return nil }
        return AgentRateLimits(fiveHour: short, weekly: long, planLabel: root["plan_type"] as? String, fetchedAt: now)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
