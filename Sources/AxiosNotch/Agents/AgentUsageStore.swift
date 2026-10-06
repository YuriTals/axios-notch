import Foundation
import Combine

/// UI state is updated on the main thread; log readers run on one serial queue.
final class AgentUsageStore: ObservableObject {
    @Published private(set) var summaries: [AgentProvider: AgentUsageSummary] = [:]
    @Published private(set) var limits: [AgentProvider: LimitState] = Dictionary(uniqueKeysWithValues: AgentProvider.allCases.map { ($0, .loading) })
    /// A failed refresh remains visible even while a valid cached reading exists.
    @Published private(set) var limitFailures: [AgentProvider: String] = [:]
    @Published private(set) var forecasts: [String: LimitForecast] = [:]
    let alerts = PassthroughSubject<LimitAlert, Never>()

    private let claudeReader: ClaudeUsageReader
    private let codexReader: CodexUsageReader
    private let antigravityReader: AntigravityUsageReader
    private let workQueue = DispatchQueue(label: "com.axiosnotch.usage", qos: .utility)
    private let refreshInterval: TimeInterval
    private let limitsInterval: TimeInterval = 120
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let fetch: (AgentProvider) async -> RateLimitClient.Result
    private var timer: Timer?
    private var limitsTimer: Timer?
    private var paused = false
    private var generation = 0
    private var requests: [AgentProvider: Task<Void, Never>] = [:]
    private var priorPolicies: [AgentProvider: LimitBackoff] = [:]
    private var backoff: [AgentProvider: LimitBackoff] = [:]
    private var alertTracker = LimitAlertTracker()
    private var forecaster = LimitForecaster()
    private var forecastExpiry: [String: Date] = [:]

    init(refreshInterval: TimeInterval = 5, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         fetch: @escaping (AgentProvider) async -> RateLimitClient.Result = RateLimitClient.fetch,
         claudeReader: ClaudeUsageReader = ClaudeUsageReader(), codexReader: CodexUsageReader = CodexUsageReader(),
         antigravityReader: AntigravityUsageReader = AntigravityUsageReader()) {
        self.claudeReader = claudeReader
        self.codexReader = codexReader
        self.antigravityReader = antigravityReader
        self.refreshInterval = refreshInterval
        self.defaults = defaults
        clock = now
        self.fetch = fetch
        for provider in AgentProvider.allCases {
            if let cached = LimitCache.load(for: provider, now: now(), defaults: defaults) { limits[provider] = .available(cached) }
            backoff[provider] = LimitBackoff.load(for: provider, defaults: defaults)
        }
    }

    func start() {
        guard timer == nil else { return }
        paused = false
        refresh()
        Task { @MainActor [weak self] in await self?.refreshLimits() }
        limitsTimer = Timer.scheduledTimer(withTimeInterval: limitsInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLimits() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.expireLimits()
            self?.refresh()
        }
    }

    func stop() {
        paused = true
        generation += 1
        limitsTimer?.invalidate(); limitsTimer = nil
        timer?.invalidate(); timer = nil
        requests.values.forEach { $0.cancel() }
        requests = [:]
        for (provider, policy) in priorPolicies { backoff[provider] = policy }
        priorPolicies = [:]
        forecasts = [:]
        forecastExpiry = [:]
    }

    private func refresh() {
        let currentGeneration = generation, now = clock()
        workQueue.async { [weak self] in
            guard let self else { return }
            let claude = self.claudeReader.refresh(now: now)
            let codex = self.codexReader.refresh(now: now)
            let antigravity = self.antigravityReader.refresh(now: now)
            DispatchQueue.main.async {
                guard !self.paused, self.generation == currentGeneration else { return }
                self.summaries[.claude] = claude
                self.summaries[.codex] = codex
                self.summaries[.antigravity] = antigravity
            }
        }
    }

    func expireLimits() {
        let now = clock()
        for provider in AgentProvider.allCases {
            if case .available(let reading) = limits[provider] {
                if let valid = reading.valid(at: now) {
                    limits[provider] = .available(valid)
                } else {
                    limits[provider] = .unavailable(limitFailures[provider] ?? tr("Dados expirados — aguardando atualização", "Expired data — waiting for refresh"))
                }
            }
            for window in LimitWindow.allCases {
                let key = "\(provider.rawValue).\(window.rawValue)"
                let limit = limits[provider]?.rateLimits?.mostUsedLimit(in: window)
                if limit == nil || forecastExpiry[key].map({ $0 <= now }) ?? true {
                    forecasts[key] = nil
                    forecastExpiry[key] = nil
                }
                if limit == nil { forecaster.forget(provider: provider, window: window) }
            }
        }
    }

    func process(limits: AgentRateLimits, for provider: AgentProvider, now: Date = Date()) {
        for window in LimitWindow.allCases {
            let key = "\(provider.rawValue).\(window.rawValue)"
            // Claude and Codex report one limit per window. Antigravity reports independent
            // quotas per model family: each is tracked on its own (never summed), and the
            // card's forecast belongs to the family the card shows, the most used one.
            let direct = window == .fiveHour ? limits.fiveHour : limits.weekly
            let tracked: [(group: AgentQuotaGroup?, limit: AgentLimit)] = direct.map { [(nil, $0)] }
                ?? (limits.quotaGroups ?? []).compactMap { group in
                    (window == .fiveHour ? group.fiveHour : group.weekly).map { (group, $0) }
                }
            let live = tracked.filter { $0.limit.resetsAt.map { $0 > now } ?? true }
            guard !live.isEmpty else {
                forecasts[key] = nil; forecastExpiry[key] = nil
                forecaster.forget(provider: provider, window: window)
                continue
            }
            var shown: (group: AgentQuotaGroup?, limit: AgentLimit)?
            for entry in live {
                forecaster.record(provider: provider, window: window, group: entry.group?.id, limit: entry.limit, now: now)
                if shown == nil || entry.limit.percent > shown!.limit.percent { shown = entry }
                if let alert = alertTracker.observe(provider: provider, window: window, group: entry.group?.id,
                                                    groupLabel: entry.group?.label, limit: entry.limit) { alerts.send(alert) }
            }
            if let shown,
               let forecast = forecaster.forecast(provider: provider, window: window, group: shown.group?.id, limit: shown.limit, now: now),
               forecast.beforeReset {
                forecasts[key] = forecast
                forecastExpiry[key] = min(now.addingTimeInterval(limitsInterval * 2),
                                          shown.limit.resetsAt ?? .distantFuture,
                                          now.addingTimeInterval(forecast.secondsToFull))
            } else {
                forecasts[key] = nil; forecastExpiry[key] = nil
            }
        }
    }

    /// Awaitable for offline tests. Each provider has at most one request in flight.
    @MainActor func refreshLimits() async {
        guard !paused else { return }
        expireLimits()
        let currentGeneration = generation
        var pending: [Task<Void, Never>] = []
        for provider in AgentProvider.allCases {
            guard requests[provider] == nil,
                  backoff[provider, default: LimitBackoff()].canFetch(now: clock()) else { continue }
            priorPolicies[provider] = backoff[provider, default: LimitBackoff()]
            backoff[provider, default: LimitBackoff()].reserve(now: clock(), for: limitsInterval)
            let task = Task { @MainActor [weak self, fetch] in
                let result = await fetch(provider)
                guard let self, !Task.isCancelled, !self.paused, self.generation == currentGeneration else { return }
                defer { self.requests[provider] = nil; self.priorPolicies[provider] = nil }
                var policy = self.backoff[provider, default: LimitBackoff()]
                let now = self.clock()
                if result.succeeded {
                    policy.succeeded(now: now, interval: self.limitsInterval)
                    self.limitFailures[provider] = nil
                    if case .available(let reading) = result.state {
                        LimitCache.save(reading, for: provider, defaults: self.defaults)
                        self.limits[provider] = reading.valid(at: now).map(LimitState.available) ?? .unavailable(tr("Dados expirados", "Expired data"))
                        self.process(limits: reading, for: provider, now: now)
                    } else { self.limits[provider] = result.state }
                } else {
                    policy.failed(now: now, retryAfter: result.retryAfter)
                    if case .unavailable(let reason) = result.state { self.limitFailures[provider] = reason }
                    self.expireLimits()
                    if case .available = self.limits[provider] {} else { self.limits[provider] = result.state }
                    for window in LimitWindow.allCases {
                        let key = "\(provider.rawValue).\(window.rawValue)"
                        self.forecasts[key] = nil; self.forecastExpiry[key] = nil
                        self.forecaster.forget(provider: provider, window: window)
                    }
                }
                self.backoff[provider] = policy
                policy.save(for: provider, defaults: self.defaults)
            }
            requests[provider] = task
            pending.append(task)
        }
        for task in pending { await task.value }
    }
}
