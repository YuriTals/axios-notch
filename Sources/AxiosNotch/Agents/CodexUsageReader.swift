import Foundation

/// Reads Codex CLI's local session logs
/// (`~/.codex/sessions/<year>/<month>/<day>/rollout-*.jsonl`) incrementally
/// and aggregates token usage. Unlike Claude Code's logs, the exact nesting
/// of the `usage` object varies by event type, so this searches a few levels
/// deep for a `usage` dictionary instead of assuming one fixed shape.
final class CodexUsageReader {
    private let calendar: Calendar
    private let tailReader = JSONLTailReader()
    private let aggregator: AgentUsageAggregator
    private let fileIndex: SessionFileIndex

    /// Per-file running token total, used only for "latest session".
    private var latestTokensByFile: [URL: AgentTokens] = [:]
    /// Codex only writes `cwd` once, on the file's `session_meta` line, so
    /// later usage lines in the same file need it remembered.
    private var lastKnownProjectByFile: [URL: String] = [:]
    /// `token_usage_record` lines carry no `model` field at all — it only
    /// appears on separate `turn_context`/`world_state` lines — so the model
    /// active for a file has to be remembered the same way as its `cwd`.
    private var lastKnownModelByFile: [URL: String] = [:]
    private var lastCumulativeByFile: [URL: AgentTokens] = [:]
    private var seenResponsesByFile: [URL: Set<String>] = [:]

    init(root: URL = CodexUsageReader.defaultRoot, calendar: Calendar = .current) {
        self.calendar = calendar
        self.aggregator = AgentUsageAggregator(calendar: calendar)
        self.fileIndex = SessionFileIndex(root: root, calendar: calendar)
    }

    static var defaultRoot: URL {
        AgentDirectories.configuration(for: .codex).appendingPathComponent("sessions", isDirectory: true)
    }

    func refresh(now: Date = Date()) -> AgentUsageSummary {
        var summary = AgentUsageSummary(provider: .codex)
        let files = fileIndex.files(now: now)
        let active = Set(files)
        tailReader.retainFiles(active)
        latestTokensByFile = latestTokensByFile.filter { active.contains($0.key) }
        lastKnownProjectByFile = lastKnownProjectByFile.filter { active.contains($0.key) }
        lastKnownModelByFile = lastKnownModelByFile.filter { active.contains($0.key) }
        lastCumulativeByFile = lastCumulativeByFile.filter { active.contains($0.key) }
        seenResponsesByFile = seenResponsesByFile.filter { active.contains($0.key) }
        aggregator.retainSources(active)
        summary.hasAnySession = !files.isEmpty

        for file in files {
            guard let read = tailReader.read(in: file) else { continue }
            if read.wasReset {
                latestTokensByFile[file] = nil
                lastKnownProjectByFile[file] = nil
                lastKnownModelByFile[file] = nil
                lastCumulativeByFile[file] = nil
                seenResponsesByFile[file] = nil
                aggregator.removeEvents(from: file)
            }
            var sessionTokens = latestTokensByFile[file] ?? AgentTokens()
            let fileDay = dayFromPath(file)

            for line in read.lines {
                guard let object = try? JSONSerialization.jsonObject(with: line) else { continue }

                if let cwd = Self.findValue(forKey: "cwd", in: object) {
                    lastKnownProjectByFile[file] = URL(fileURLWithPath: cwd).lastPathComponent
                }
                if let model = Self.findValue(forKey: "model", in: object) {
                    lastKnownModelByFile[file] = model
                }

                guard let entry = Self.parseUsage(object) else { continue }
                if let id = entry.id, !seenResponsesByFile[file, default: []].insert(id).inserted { continue }
                let tokens: AgentTokens
                if let cumulative = entry.cumulative {
                    let previous = lastCumulativeByFile[file] ?? AgentTokens()
                    tokens = cumulative.totalTokens < previous.totalTokens
                        ? entry.tokens : cumulative.subtracting(previous)
                    lastCumulativeByFile[file] = cumulative
                } else {
                    tokens = entry.tokens
                    lastCumulativeByFile[file, default: AgentTokens()] += tokens
                }
                guard tokens.totalTokens > 0 else { continue }
                sessionTokens += tokens
                let date = entry.timestamp ?? fileDay ?? now
                aggregator.ingest(AgentUsageEvent(
                    date: date,
                    model: entry.model ?? lastKnownModelByFile[file],
                    project: lastKnownProjectByFile[file],
                    tokens: tokens, id: entry.id.map { file.path + ":" + $0 }, source: file
                ))
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
        return latestTokensByFile[newest] ?? AgentTokens()
    }

    var trackedFileCount: Int { latestTokensByFile.count }

    private func modificationDate(_ url: URL) -> Date {
        (try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }


    /// Fallback for older logs without a valid event timestamp. The folder
    /// describes session creation, not when a resumed session produces usage.
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
        let timestamp: Date?
        var cumulative: AgentTokens? = nil
        var id: String? = nil
    }

    /// Recursively looks for a `"usage"` object carrying token counts,
    /// tolerant of whatever event/payload nesting the line uses, plus a
    /// nearby `"model"` string if one is present.
    static func parseUsage(_ object: Any) -> UsageEntry? {
        let root = object as? [String: Any]
        let payload = root?["payload"] as? [String: Any] ?? root
        let info = payload?["info"] as? [String: Any]
        let total = info?["total_token_usage"] as? [String: Any]
        let last = info?["last_token_usage"] as? [String: Any]
        let usage = last ?? total ?? findUsageDictionary(in: object, depth: 0)
        guard let usage else { return nil }

        let tokens = tokens(from: usage)
        let model = findValue(forKey: "model", in: object)
        let timestamp = ((object as? [String: Any])?["timestamp"] as? String)
            .flatMap(ClaudeUsageReader.parseTimestamp)
        let cumulative = total ?? (payload?["thread_token_usage"] as? [String: Any])
        return UsageEntry(tokens: tokens, model: model, timestamp: timestamp,
                          cumulative: cumulative.map { Self.tokens(from: $0) },
                          id: findValue(forKey: "response_id", in: object))
    }

    /// Codex reports cache buckets inside input, and reasoning inside output.
    private static func tokens(from usage: [String: Any]) -> AgentTokens {
        let input = max(0, usage["input_tokens"] as? Int ?? 0)
        let read = min(input, max(0, usage["cached_input_tokens"] as? Int ?? 0))
        let write = min(input - read, max(0, usage["cache_write_input_tokens"] as? Int ?? 0))
        let output = max(0, usage["output_tokens"] as? Int ?? 0)
        return AgentTokens(input: input - read - write, cacheWrite: write,
                           cacheRead: read, output: output,
                           reasoning: min(output, max(0, usage["reasoning_output_tokens"] as? Int ?? 0)))
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
