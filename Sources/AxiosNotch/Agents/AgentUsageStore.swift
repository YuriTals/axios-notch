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
    private let limitsInterval: TimeInterval = 60

    init(refreshInterval: TimeInterval = 5) {
        self.refreshInterval = refreshInterval
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
    private func refreshLimits() {
        for provider in AgentProvider.allCases {
            Task { [weak self] in
                let result = await RateLimitClient.fetch(provider)
                guard let self else { return }
                await MainActor.run {
                    if case .unavailable = result, case .available = self.limits[provider] { return }
                    self.limits[provider] = result
                }
            }
        }
    }
}
