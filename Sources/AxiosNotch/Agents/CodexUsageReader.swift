import Foundation

/// Reads Codex CLI's local session logs
/// (`~/.codex/sessions/<year>/<month>/<day>/rollout-*.jsonl`) incrementally
/// and aggregates token usage. Unlike Claude Code's logs, the exact nesting
/// of the `usage` object varies by event type, so this searches a few levels
/// deep for a `usage` dictionary instead of assuming one fixed shape.
final class CodexUsageReader {
    private let root: URL
    private let calendar: Calendar
    private let tailReader = JSONLTailReader()
    private let aggregator: AgentUsageAggregator

    /// Per-file running token total, used only for "latest session".
    private var latestTokensByFile: [URL: AgentTokens] = [:]
    /// Codex only writes `cwd` once, on the file's `session_meta` line, so
    /// later usage lines in the same file need it remembered.
    private var lastKnownProjectByFile: [URL: String] = [:]
    /// `token_usage_record` lines carry no `model` field at all — it only
    /// appears on separate `turn_context`/`world_state` lines — so the model
    /// active for a file has to be remembered the same way as its `cwd`.
    private var lastKnownModelByFile: [URL: String] = [:]

    init(root: URL = CodexUsageReader.defaultRoot, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
        self.aggregator = AgentUsageAggregator(calendar: calendar)
    }

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    func refresh(now: Date = Date()) -> AgentUsageSummary {
        var summary = AgentUsageSummary(provider: .codex)
        let files = recentSessionFiles(now: now)
        summary.hasAnySession = !files.isEmpty

        for file in files {
            guard let lines = tailReader.newLines(in: file) else { continue }
            var sessionTokens = latestTokensByFile[file] ?? AgentTokens()
            let fileDay = dayFromPath(file)

            for line in lines {
                guard let object = try? JSONSerialization.jsonObject(with: line) else { continue }

                if let cwd = Self.findValue(forKey: "cwd", in: object) {
                    lastKnownProjectByFile[file] = URL(fileURLWithPath: cwd).lastPathComponent
                }
                if let model = Self.findValue(forKey: "model", in: object) {
                    lastKnownModelByFile[file] = model
                }

                guard let entry = Self.parseUsage(object) else { continue }
                sessionTokens += entry.tokens
                let date = fileDay ?? now
                aggregator.ingest(AgentUsageEvent(
                    date: date,
                    model: entry.model ?? lastKnownModelByFile[file],
                    project: lastKnownProjectByFile[file],
                    tokens: entry.tokens
                ))
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

    /// Codex lays sessions out as `.../sessions/<year>/<month>/<day>/rollout-*.jsonl`,
    /// which is a more reliable source of the session's date than any single
    /// line inside it.
    private func dayFromPath(_ file: URL) -> Date? {
        let components = file.deletingLastPathComponent().pathComponents.suffix(3)
        guard components.count == 3,
              let year = Int(components[components.startIndex]),
              let month = Int(components[components.index(after: components.startIndex)]),
              let day = Int(components[components.index(components.startIndex, offsetBy: 2)])
        else { return nil }

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        return calendar.date(from: dateComponents)
    }

    struct UsageEntry {
        let tokens: AgentTokens
        let model: String?
    }

    /// Recursively looks for a `"usage"` object carrying token counts,
    /// tolerant of whatever event/payload nesting the line uses, plus a
    /// nearby `"model"` string if one is present.
    static func parseUsage(_ object: Any) -> UsageEntry? {
        guard let usage = findUsageDictionary(in: object, depth: 0) else { return nil }

        let tokens = AgentTokens(
            input: usage["input_tokens"] as? Int ?? 0,
            cacheWrite: usage["cache_write_input_tokens"] as? Int ?? 0,
            cacheRead: usage["cached_input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            reasoning: usage["reasoning_output_tokens"] as? Int ?? 0
        )
        let model = findValue(forKey: "model", in: object)
        return UsageEntry(tokens: tokens, model: model)
    }

    static func parseUsage(_ line: Data) -> UsageEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: line) else { return nil }
        return parseUsage(object)
    }

    private static func findUsageDictionary(in json: Any, depth: Int) -> [String: Any]? {
        guard depth < 6 else { return nil }

        if let dict = json as? [String: Any] {
            if let usage = dict["usage"] as? [String: Any],
               usage["input_tokens"] != nil || usage["total_tokens"] != nil {
                return usage
            }
            for value in dict.values {
                if let found = findUsageDictionary(in: value, depth: depth + 1) {
                    return found
                }
            }
        } else if let array = json as? [Any] {
            for value in array {
                if let found = findUsageDictionary(in: value, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }

    /// Recursively looks for a string value under `key`, tolerant of nesting.
    static func findValue(forKey key: String, in json: Any, depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }

        if let dict = json as? [String: Any] {
            if let value = dict[key] as? String { return value }
            for value in dict.values {
                if let found = findValue(forKey: key, in: value, depth: depth + 1) {
                    return found
                }
            }
        } else if let array = json as? [Any] {
            for value in array {
                if let found = findValue(forKey: key, in: value, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }
}
