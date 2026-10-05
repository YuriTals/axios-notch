import Foundation

/// Reads only the full CLI transcript; the short transcript mirrors it and
/// must not be counted again. Prompts, replies and OAuth data are not retained.
final class AntigravityUsageReader {
    private let tailReader = JSONLTailReader()
    private let aggregator: AgentUsageAggregator
    private let fileIndex: SessionFileIndex
    private var tokensByFile: [URL: [Int: AgentTokens]] = [:]

    init(root: URL = AgentDirectories.configuration(for: .antigravity).appendingPathComponent("brain"),
         calendar: Calendar = .current) {
        aggregator = AgentUsageAggregator(calendar: calendar)
        fileIndex = SessionFileIndex(root: root, calendar: calendar, includeHidden: true)
    }

    func refresh(now: Date = Date()) -> AgentUsageSummary {
        let files = fileIndex.files(now: now).filter { $0.lastPathComponent == "transcript_full.jsonl" }
        let active = Set(files)
        tailReader.retainFiles(active)
        tokensByFile = tokensByFile.filter { active.contains($0.key) }
        aggregator.retainSources(active)
        for file in files {
            guard let read = tailReader.read(in: file) else { continue }
            if read.wasReset {
                tokensByFile[file] = nil
                aggregator.removeEvents(from: file)
            }
            for line in read.lines {
                guard let event = Self.parseUsage(line, source: file) else { continue }
                tokensByFile[file, default: [:]][event.step] = event.event.tokens
                aggregator.ingest(event.event)
            }
        }
        let b = aggregator.snapshot(now: now)
        var summary = AgentUsageSummary(provider: .antigravity)
        summary.hasAnySession = !files.isEmpty
        summary.todayTokens = b.todayTokens
        summary.todayCostEstimate = b.todayCostEstimate
        summary.hourlyCostEstimatesToday = b.hourlyCostEstimatesToday
        summary.modelSpendToday = b.modelSpendToday
        summary.projectSpendToday = b.projectSpendToday
        summary.dailyHistory = b.dailyHistory
        summary.historyCostEstimate = b.historyCostEstimate
        summary.activeDaysInHistory = b.activeDaysInHistory
        summary.busiestDay = b.busiestDay
        summary.fiveHourBlock = b.fiveHourBlock
        summary.week = b.week
        summary.weekDailyCostEstimates = b.weekDailyCostEstimates
        summary.weekModels = b.weekModels
        summary.lastActivity = aggregator.lastActivity
        if let latest = files.max(by: { modificationDate($0) < modificationDate($1) }) {
            summary.latestSessionTokens = tokensByFile[latest, default: [:]].values.reduce(AgentTokens(), +)
        }
        return summary
    }

    private func modificationDate(_ file: URL) -> Date {
        (try? URL(fileURLWithPath: file.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    struct Entry { let step: Int; let event: AgentUsageEvent }

    static func parseUsage(_ line: Data, source: URL) -> Entry? {
        guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              row["source"] as? String == "MODEL", row["status"] as? String == "DONE",
              let step = row["step_index"] as? Int, step >= 0,
              let timestamp = row["created_at"] as? String,
              let date = ClaudeUsageReader.parseTimestamp(timestamp),
              let input = row["input_tokens"] as? Int,
              let output = row["output_tokens"] as? Int,
              input >= 0, output >= 0 else { return nil }
        // CLI transcript input excludes cache (observed cache > input).
        // Thinking is already part of output; never add it to the total.
        let tokens = AgentTokens(input: input,
                                 cacheRead: max(0, row["cache_read_tokens"] as? Int ?? 0),
                                 output: output,
                                 reasoning: min(output, max(0, row["thinking_tokens"] as? Int ?? 0)))
        guard tokens.totalTokens > 0 else { return nil }
        return Entry(step: step, event: AgentUsageEvent(date: date,
            model: row["model"] as? String, project: nil, tokens: tokens,
            id: source.path + ":" + String(step), source: source))
    }
}
