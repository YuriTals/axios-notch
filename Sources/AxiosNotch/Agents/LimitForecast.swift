import Foundation

/// "At this pace you'll hit the limit in about 40 minutes."
struct LimitForecast: Equatable {
    /// Seconds from now until the window reaches 100 %.
    let secondsToFull: TimeInterval
    /// Whether that happens before the window resets on its own. Only then is
    /// it worth telling the user.
    let beforeReset: Bool
}

/// Projects each window's recent growth forward. Keeps the readings of the
/// last hour per provider/window and fits a straight line through them (least
/// squares), so one noisy reading doesn't swing the estimate.
///
/// It stays quiet until it has enough to say something true: at least three
/// readings spread over ten minutes, and usage actually climbing.
struct LimitForecaster {
    static let lookback: TimeInterval = 60 * 60
    static let minimumSpan: TimeInterval = 10 * 60
    static let minimumSamples = 3
    /// Below this the pace is noise (≈ 1 % an hour).
    static let minimumSlope = 1.0 / 3600
    static let horizon: TimeInterval = 7 * 24 * 3600

    /// `group` separates independent quotas of one provider (Antigravity model families).
    private struct Key: Hashable { let provider: AgentProvider; let window: LimitWindow; var group: String? = nil }
    private struct Sample { let date: Date; let percent: Double }
    private var samples: [Key: [Sample]] = [:]
    private var lastReset: [Key: Date] = [:]

    /// Forgets the window's history, including every group's.
    mutating func forget(provider: AgentProvider, window: LimitWindow) {
        for key in samples.keys where key.provider == provider && key.window == window { samples[key] = nil }
        for key in lastReset.keys where key.provider == provider && key.window == window { lastReset[key] = nil }
    }

    mutating func record(provider: AgentProvider, window: LimitWindow, group: String? = nil, limit: AgentLimit, now: Date) {
        let key = Key(provider: provider, window: window, group: group)
        var list = samples[key] ?? []

        // A new window (usage dropped, or the reset time moved) starts a new history.
        if let last = list.last, limit.percent < last.percent - 5 { list = [] }
        if let reset = limit.resetsAt, let previous = lastReset[key], abs(reset.timeIntervalSince(previous)) > 300 { list = [] }
        if let reset = limit.resetsAt { lastReset[key] = reset }

        list.append(Sample(date: now, percent: limit.percent))
        list.removeAll { now.timeIntervalSince($0.date) > Self.lookback }
        samples[key] = list
    }

    func forecast(provider: AgentProvider, window: LimitWindow, group: String? = nil, limit: AgentLimit, now: Date) -> LimitForecast? {
        let list = (samples[Key(provider: provider, window: window, group: group)] ?? [])
            .filter { now.timeIntervalSince($0.date) <= Self.lookback }
        guard list.count >= Self.minimumSamples,
              let first = list.first, let last = list.last,
              last.date.timeIntervalSince(first.date) >= Self.minimumSpan else { return nil }

        // Slope of percent per second by least squares, times measured from the first reading.
        let xs = list.map { $0.date.timeIntervalSince(first.date) }
        let ys = list.map(\.percent)
        let n = Double(list.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard denominator > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / denominator
        guard slope >= Self.minimumSlope else { return nil }

        let remaining = 100 - limit.percent
        guard remaining > 0 else { return nil }
        let seconds = remaining / slope
        guard seconds <= Self.horizon else { return nil }
        let beforeReset = limit.resetsAt.map { now.addingTimeInterval(seconds) < $0 } ?? true
        return LimitForecast(secondsToFull: seconds, beforeReset: beforeReset)
    }
}
