import Foundation
import Combine

/// Polls the local Claude Code and Codex readers on a background queue and
/// publishes their summaries for the notch UI to observe.
final class AgentUsageStore: ObservableObject {
    @Published private(set) var summaries: [AgentProvider: AgentUsageSummary] = [:]

    private let claudeReader = ClaudeUsageReader()
    private let codexReader = CodexUsageReader()
    private let workQueue = DispatchQueue(label: "com.axiosnotch.usage", qos: .utility)
    private let refreshInterval: TimeInterval
    private var timer: Timer?

    init(refreshInterval: TimeInterval = 5) {
        self.refreshInterval = refreshInterval
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
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
}
