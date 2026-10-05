import Foundation

/// Reads Claude Code's local session logs
/// (`~/.claude/projects/<cwd-slug>/<uuid>.jsonl`) incrementally and
/// aggregates token usage. Each line is one JSON object; the ones worth
/// reading have `"type":"assistant"` and a `message.usage` block.
final class ClaudeUsageReader {
    private let root: URL
    private let calendar: Calendar
    private let tailReader = JSONLTailReader()
    private let aggregator: AgentUsageAggregator
    private let fileIndex: SessionFileIndex

    /// Per-file running token total, used only for "latest session" — a
    /// separate concern from the aggregator's date/model/project breakdown.
    private var latestTokensByFile: [URL: [String: AgentTokens]] = [:]

    init(root: URL = ClaudeUsageReader.defaultRoot, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
        self.aggregator = AgentUsageAggregator(calendar: calendar)
        self.fileIndex = SessionFileIndex(root: root, calendar: calendar)
    }

    static var defaultRoot: URL {
        AgentDirectories.configuration(for: .claude).appendingPathComponent("projects", isDirectory: true)
    }

    /// Rescans every session file under `root`, reading only what changed
    /// since the last call, and returns the current summary.
    func refresh(now: Date = Date()) -> AgentUsageSummary {
        var summary = AgentUsageSummary(provider: .claude)
        let files = fileIndex.files(now: now)
        let active = Set(files)
        tailReader.retainFiles(active)
        latestTokensByFile = latestTokensByFile.filter { active.contains($0.key) }
        aggregator.retainSources(active)
        summary.hasAnySession = !files.isEmpty

        for file in files {
            guard let read = tailReader.read(in: file) else { continue }
            if read.wasReset {
                latestTokensByFile[file] = nil
                aggregator.removeEvents(from: file)
            }
            var sessionTokens = latestTokensByFile[file] ?? [:]
            for line in read.lines {
                guard let entry = Self.parseAssistantUsage(line) else { continue }
                let date = entry.timestamp ?? now
                let id = entry.id.map { file.path + ":" + $0 }
                aggregator.ingest(AgentUsageEvent(date: date, model: entry.model, project: entry.project, tokens: entry.tokens, id: id, source: file))
                // Entries without an id are never duplicates; give each its own slot.
                sessionTokens[entry.id ?? UUID().uuidString] = entry.tokens
            }
            latestTokensByFile[file] = sessionTokens
        }

        let breakdown = aggregator.snapshot(now: now)
        summary.todayTokens = breakdown.todayTokens
        summary.todayCostEstimate = breakdown.todayCostEstimate
        summary.hourlyCostEstimatesToday = breakdown.hourlyCostEstimatesToday
        summary.modelSpendToday = breakdown.modelSpendToday
        summary.projectSpendToday = breakdown.projectSpendToday
        summary.dailyHistory = breakdown.dailyHistory
        summary.historyCostEstimate = breakdown.historyCostEstimate
        summary.activeDaysInHistory = breakdown.activeDaysInHistory
        summary.busiestDay = breakdown.busiestDay
        summary.fiveHourBlock = breakdown.fiveHourBlock
        summary.week = breakdown.week
        summary.weekDailyCostEstimates = breakdown.weekDailyCostEstimates
        summary.weekModels = breakdown.weekModels
        summary.latestSessionTokens = mostRecentSessionTokens(among: files)
        summary.lastActivity = aggregator.lastActivity
        return summary
    }

    private func mostRecentSessionTokens(among files: [URL]) -> AgentTokens {
        guard let newest = files.max(by: { modificationDate($0) < modificationDate($1) }) else {
            return AgentTokens()
        }
        return (latestTokensByFile[newest] ?? [:]).values.reduce(AgentTokens(), +)
    }

    var trackedFileCount: Int { latestTokensByFile.count }

    private func modificationDate(_ url: URL) -> Date {
        (try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    struct UsageEntry {
        let tokens: AgentTokens
        let model: String?
        let project: String?
        let timestamp: Date?
        let id: String?
    }

    static func parseAssistantUsage(_ line: Data) -> UsageEntry? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "assistant",
            let message = object["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        let tokens = AgentTokens(
            input: usage["input_tokens"] as? Int ?? 0,
            cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0
        )
        let model = message["model"] as? String
        let project = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp)
        let id = (message["id"] as? String).map { "\($0):\(object["requestId"] as? String ?? "")" }
        return UsageEntry(tokens: tokens, model: model, project: project, timestamp: timestamp, id: id)
    }

    /// Claude Code timestamps are usually ISO-8601 with fractional seconds,
    /// but this falls back to the plain form just in case.
    static func parseTimestamp(_ string: String) -> Date? {
        isoFormatterWithFraction.date(from: string) ?? isoFormatter.date(from: string)
    }

    private static let isoFormatterWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()
}
