import Foundation

/// Decides when the plan-usage endpoints may be asked again. A provider that
/// answers "too many requests" (HTTP 429) must be left alone for a while —
/// the old fixed 60 s poll just kept hitting it, so the percentages never
/// came back. Success resets everything.
struct LimitBackoff: Codable {
    private(set) var failures = 0
    private(set) var nextAllowed = Date.distantPast

    /// Remembered across launches: reopening the app must not count as a
    /// fresh start, or every restart would hit a provider that said "wait".
    private static func key(_ provider: AgentProvider) -> String { "limitBackoff.\(provider.rawValue)" }

    static func load(for provider: AgentProvider, defaults: UserDefaults = .standard) -> LimitBackoff {
        defaults.data(forKey: key(provider)).flatMap { try? JSONDecoder().decode(LimitBackoff.self, from: $0) } ?? LimitBackoff()
    }

    func save(for provider: AgentProvider, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(provider)) }
    }

    static let minimumRetryAfter: TimeInterval = 30
    static let maximumDelay: TimeInterval = 15 * 60

    func canFetch(now: Date) -> Bool { now >= nextAllowed }

    /// Holds the slot while a request is in flight, without touching the
    /// failure count, so overlapping timer ticks can't fetch twice.
    mutating func reserve(now: Date, for interval: TimeInterval) {
        nextAllowed = now.addingTimeInterval(interval)
    }

    mutating func succeeded(now: Date, interval: TimeInterval) {
        failures = 0
        nextAllowed = now.addingTimeInterval(interval)
    }

    /// `retryAfter` is the server's own `Retry-After` when it sent one;
    /// otherwise wait 1, 2, 4, 8… minutes, capped.
    mutating func failed(now: Date, retryAfter: TimeInterval?) {
        failures += 1
        let delay: TimeInterval
        if let retryAfter {
            delay = min(max(retryAfter, Self.minimumRetryAfter), 30 * 60)
        } else {
            delay = min(Self.maximumDelay, 60 * pow(2, Double(failures - 1)))
        }
        nextAllowed = now.addingTimeInterval(delay)
    }
}

/// The last good limits, kept across launches so the notch has something true
/// to show right after a restart instead of waiting on (or failing) a request.
enum LimitCache {
    private static let maxAge: TimeInterval = 6 * 3600

    private static func key(_ provider: AgentProvider) -> String { "limitsCache.\(provider.rawValue)" }

    static func save(_ limits: AgentRateLimits, for provider: AgentProvider, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(limits) { defaults.set(data, forKey: key(provider)) }
    }

    /// Windows that have already reset are dropped: their percentage no longer
    /// describes anything.
    static func load(for provider: AgentProvider, now: Date = Date(), defaults: UserDefaults = .standard) -> AgentRateLimits? {
        guard let data = defaults.data(forKey: key(provider)),
              var limits = try? JSONDecoder().decode(AgentRateLimits.self, from: data),
              now.timeIntervalSince(limits.fetchedAt) < maxAge else { return nil }
        func live(_ limit: AgentLimit?) -> AgentLimit? {
            guard let limit else { return nil }
            if let reset = limit.resetsAt, reset <= now { return nil }
            return limit
        }
        limits.fiveHour = live(limits.fiveHour)
        limits.weekly = live(limits.weekly)
        limits.modelLimits = limits.modelLimits.compactMap { entry in
            live(entry.limit).map { AgentModelLimit(label: entry.label, limit: $0) }
        }
        return limits.fiveHour == nil && limits.weekly == nil ? nil : limits
    }
}
