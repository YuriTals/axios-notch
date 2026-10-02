import Foundation
import Combine

/// Polls the local Claude Code and Codex readers on a background queue and
/// publishes their summaries for the notch UI to observe.
final class AgentUsageStore: ObservableObject {
    @Published private(set) var summaries: [AgentProvider: AgentUsageSummary] = [:]
    /// Real % of the 5-hour/weekly plan windows, as the providers report it.
    @Published private(set) var limits: [AgentProvider: LimitState] = [.claude: .loading, .codex: .loading]

    private let claudeReader = ClaudeUsageReader()
    private let codexReader = CodexUsageReader()
    private let workQueue = DispatchQueue(label: "com.axiosnotch.usage", qos: .utility)
    private let refreshInterval: TimeInterval
    private var timer: Timer?
    private var limitsTimer: Timer?
    /// How often to ask each provider for plan usage. Gentle on purpose: the
    /// endpoints answer 429 to clients that poll too hard, and other apps may
    /// be polling the same token.
    private let limitsInterval: TimeInterval = 120
    private var backoff: [AgentProvider: LimitBackoff] = [:]
    private var alertTracker = LimitAlertTracker()
    private var forecaster = LimitForecaster()
    /// "At this pace…" projections, keyed `provider.window` (see `forecast(for:window:)`).
    @Published private(set) var forecasts: [String: LimitForecast] = [:]
    /// Fires when a limit crosses 80 %/90 % or a high window starts over.
    let alerts = PassthroughSubject<LimitAlert, Never>()

    init(refreshInterval: TimeInterval = 5) {
        self.refreshInterval = refreshInterval
        // Show the last good numbers right away, while the first request runs.
        for provider in AgentProvider.allCases {
            if let cached = LimitCache.load(for: provider) { limits[provider] = .available(cached) }
            backoff[provider] = LimitBackoff.load(for: provider)
        }
    }

    func start() {
        refresh()
        refreshLimits()
        limitsTimer = Timer.scheduledTimer(withTimeInterval: limitsInterval, repeats: true) { [weak self] _ in
            self?.refreshLimits()
        }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        limitsTimer?.invalidate()
        limitsTimer = nil
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let claude = self.claudeReader.refresh()
            let codex = self.codexReader.refresh()
            DispatchQueue.main.async {
                self.summaries[.claude] = claude
                self.summaries[.codex] = codex
            }
        }
    }

    /// Asks each provider for its real plan usage. A failed fetch keeps the
    /// last good numbers on screen unless there never were any.
    /// What to do with a fresh reading of a provider's limits: feed the
    /// forecaster, publish its projection, and raise any 80 %/90 % alert.
    func process(limits: AgentRateLimits, for provider: AgentProvider, now: Date = Date()) {
        let windows: [(LimitWindow, AgentLimit?)] = [(.fiveHour, limits.fiveHour), (.weekly, limits.weekly)]
        for (window, limit) in windows {
            guard let limit else { continue }
            forecaster.record(provider: provider, window: window, limit: limit, now: now)
            let key = "\(provider.rawValue).\(window.rawValue)"
            if let forecast = forecaster.forecast(provider: provider, window: window, limit: limit, now: now), forecast.beforeReset {
                forecasts[key] = forecast
            } else {
                forecasts[key] = nil
            }
            if let alert = alertTracker.observe(provider: provider, window: window, limit: limit) {
                alerts.send(alert)
            }
        }
    }

    private func refreshLimits() {
        for provider in AgentProvider.allCases {
            guard backoff[provider, default: LimitBackoff()].canFetch(now: Date()) else { continue }
            // Claim the slot now so overlapping timer ticks can't double-fetch.
            backoff[provider, default: LimitBackoff()].reserve(now: Date(), for: limitsInterval)
            backoff[provider]?.save(for: provider)
            Task { [weak self] in
                let result = await RateLimitClient.fetch(provider)
                guard let self else { return }
                await MainActor.run {
                    var policy = self.backoff[provider, default: LimitBackoff()]
                    if result.succeeded {
                        policy.succeeded(now: Date(), interval: self.limitsInterval)
                        if case .available(let limits) = result.state {
                            LimitCache.save(limits, for: provider)
                            self.process(limits: limits, for: provider)
                        }
                        self.limits[provider] = result.state
                    } else {
                        policy.failed(now: Date(), retryAfter: result.retryAfter)
                        // Keep showing the last good numbers; only say why when there are none.
                        if case .available = self.limits[provider] {} else { self.limits[provider] = result.state }
                    }
                    self.backoff[provider] = policy
                    policy.save(for: provider)
                }
            }
        }
    }
}
