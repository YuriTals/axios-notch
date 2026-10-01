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

    /// Per-file running token total, used only for "latest session" — a
    /// separate concern from the aggregator's date/model/project breakdown.
    private var latestTokensByFile: [URL: AgentTokens] = [:]

    init(root: URL = ClaudeUsageReader.defaultRoot, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
        self.aggregator = AgentUsageAggregator(calendar: calendar)
    }

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Rescans every session file under `root`, reading only what changed
    /// since the last call, and returns the current summary.
    func refresh(now: Date = Date()) -> AgentUsageSummary {
        var summary = AgentUsageSummary(provider: .claude)
        let files = recentSessionFiles(now: now)
        summary.hasAnySession = !files.isEmpty

        for file in files {
            guard let lines = tailReader.newLines(in: file) else { continue }
            var sessionTokens = latestTokensByFile[file] ?? AgentTokens()
            for line in lines {
                guard let entry = Self.parseAssistantUsage(line) else { continue }
                sessionTokens += entry.tokens
                let date = entry.timestamp ?? now
                aggregator.ingest(AgentUsageEvent(date: date, model: entry.model, project: entry.project, tokens: entry.tokens))
            }
            latestTokensByFile[file] = sessionTokens
        }

        let breakdown = aggregator.snapshot(now: now)
        summary.todayTokens = breakdown.todayTokens
        summary.estimatedCostToday = breakdown.estimatedCostToday
        summary.hourlySpendToday = breakdown.hourlySpendToday
        summary.modelSpendToday = breakdown.modelSpendToday
        summary.projectSpendToday = breakdown.projectSpendToday
        summary.dailyHistory = breakdown.dailyHistory
        summary.totalCostInHistory = breakdown.totalCostInHistory
        summary.activeDaysInHistory = breakdown.activeDaysInHistory
        summary.busiestDay = breakdown.busiestDay
        summary.latestSessionTokens = mostRecentSessionTokens(among: files)
        summary.lastActivity = aggregator.lastActivity
        return summary
    }

    private func mostRecentSessionTokens(among files: [URL]) -> AgentTokens {
        guard let newest = files.max(by: { modificationDate($0) < modificationDate($1) }) else {
            return AgentTokens()
        }
        return latestTokensByFile[newest] ?? AgentTokens()
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Only files touched within the aggregator's retention window can
    /// contain lines worth aggregating — a file's `mtime` is its *last*
    /// write, so an older one can't hold anything more recent than that.
    private func recentSessionFiles(now: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = calendar.date(byAdding: .day, value: -91, to: now) ?? .distantPast
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" && modificationDate($0) >= cutoff }
    }

    struct UsageEntry {
        let tokens: AgentTokens
        let model: String?
        let project: String?
        let timestamp: Date?
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
        return UsageEntry(tokens: tokens, model: model, project: project, timestamp: timestamp)
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
