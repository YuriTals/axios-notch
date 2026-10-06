import XCTest
@testable import AxiosNotch

final class CodexUsageReaderTests: XCTestCase {
    private var tempRoot: URL!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("axios-notch-codex-\(UUID().uuidString)")
        calendar = .current
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Codex lays sessions out as .../sessions/<year>/<month>/<day>/rollout-*.jsonl;
    /// building today's directory from the same `now` the reader sees keeps
    /// the "today" comparison exact regardless of when the test runs.
    private func todaysSessionDirectory(now: Date) throws -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let dir = tempRoot
            .appendingPathComponent(String(format: "%04d", components.year!))
            .appendingPathComponent(String(format: "%02d", components.month!))
            .appendingPathComponent(String(format: "%02d", components.day!))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testFindsUsageNestedInsideEventPayload() throws {
        let now = Date()
        let dir = try todaysSessionDirectory(now: now)
        let file = dir.appendingPathComponent("rollout-test.jsonl")

        let contents = """
        {"type":"session_meta","cwd":"/tmp","cli_version":"0.159.2"}
        {"type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5.6-terra","usage":{"input_tokens":200,"cached_input_tokens":50,"cache_write_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":5,"total_tokens":235}}}}

        """
        try contents.write(to: file, atomically: true, encoding: .utf8)

        let reader = CodexUsageReader(root: tempRoot, calendar: calendar)
        let summary = reader.refresh(now: now)

        XCTAssertTrue(summary.hasAnySession)
        XCTAssertEqual(summary.todayTokens.input, 150)
        XCTAssertEqual(summary.todayTokens.cacheRead, 50)
        XCTAssertEqual(summary.todayTokens.output, 30)
        XCTAssertEqual(summary.todayTokens.reasoning, 5)
    }

    /// Mirrors the real shape found in an actual `~/.codex/sessions/.../rollout-*.jsonl`
    /// file: `cwd` and `model` only ever appear on `session_meta`/`turn_context`
    /// lines, never on the `token_usage_record` lines that carry `usage` — so a
    /// model/project seen earlier in the file must carry forward to later usage.
    func testCarriesModelAndProjectForwardFromEarlierLines() throws {
        let now = Date()
        let dir = try todaysSessionDirectory(now: now)
        let file = dir.appendingPathComponent("rollout-real-shape.jsonl")

        let contents = """
        {"type":"session_meta","payload":{"cwd":"/Users/dev/Downloads/GBA","cli_version":"0.154.0-alpha.6.2"}}
        {"type":"turn_context","payload":{"cwd":"/Users/dev/Downloads/GBA","model":"gpt-5.6-terra"}}
        {"type":"token_usage_record","payload":{"usage":{"input_tokens":27890,"cached_input_tokens":21248,"cache_write_input_tokens":0,"output_tokens":127,"reasoning_output_tokens":12,"total_tokens":28017}}}

        """
        try contents.write(to: file, atomically: true, encoding: .utf8)

        let reader = CodexUsageReader(root: tempRoot, calendar: calendar)
        let summary = reader.refresh(now: now)

        XCTAssertEqual(summary.todayTokens.input, 6642)
        XCTAssertEqual(summary.todayTokens.totalTokens, 28017)
        XCTAssertEqual(summary.modelSpendToday.first?.name, "gpt-5.6-terra")
        XCTAssertEqual(summary.projectSpendToday.first?.name, "GBA")
        XCTAssertNotNil(summary.estimatedCostToday, "a known model carried forward should still price the usage")
    }

    func testFallsBackToFilePathDayWithoutTimestamp() throws {
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return XCTFail("could not compute yesterday")
        }
        let dir = try todaysSessionDirectory(now: yesterday)
        let file = dir.appendingPathComponent("rollout-old.jsonl")

        let contents = """
        {"usage":{"input_tokens":999,"total_tokens":999}}

        """
        try contents.write(to: file, atomically: true, encoding: .utf8)

        let reader = CodexUsageReader(root: tempRoot, calendar: calendar)
        let summary = reader.refresh(now: now)

        XCTAssertTrue(summary.hasAnySession)
        XCTAssertEqual(summary.todayTokens.totalTokens, 0, "a session filed under yesterday's folder shouldn't count as today")
        XCTAssertEqual(summary.latestSessionTokens.totalTokens, 999, "but it should still count toward the latest session total")
    }

    func testResumedSessionCountsUsageOnTheEventDay() throws {
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(14 * 3600)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let dir = try todaysSessionDirectory(now: yesterday)
        let file = dir.appendingPathComponent("rollout-resumed.jsonl")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let contents = """
        {"timestamp":"\(formatter.string(from: yesterday))","usage":{"input_tokens":100,"total_tokens":100}}
        {"timestamp":"\(formatter.string(from: now.addingTimeInterval(-60)))","usage":{"input_tokens":200,"total_tokens":200}}

        """
        try contents.write(to: file, atomically: true, encoding: .utf8)

        let summary = CodexUsageReader(root: tempRoot, calendar: calendar).refresh(now: now)
        XCTAssertEqual(summary.todayTokens.input, 200)
        XCTAssertEqual(summary.latestSessionTokens.input, 300)
        XCTAssertEqual(summary.fiveHourBlock?.tokens.input, 200)
        XCTAssertEqual(summary.lastActivity?.timeIntervalSince1970 ?? 0,
                       now.addingTimeInterval(-60).timeIntervalSince1970, accuracy: 0.001)
    }

    func testAfternoonUsageKeepsAnActiveFiveHourBlock() throws {
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(15 * 3600)
        let dir = try todaysSessionDirectory(now: now)
        let file = dir.appendingPathComponent("rollout-afternoon.jsonl")
        let timestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        try "{\"timestamp\":\"\(timestamp)\",\"usage\":{\"input_tokens\":123,\"total_tokens\":123}}\n"
            .write(to: file, atomically: true, encoding: .utf8)

        let summary = CodexUsageReader(root: tempRoot, calendar: calendar).refresh(now: now)
        XCTAssertEqual(summary.fiveHourBlock?.tokens.input, 123)
        XCTAssertEqual(summary.todayTokens.input, 123)
    }

    func testInvalidTimestampFallsBackToSessionDay() throws {
        let now = Date()
        let dir = try todaysSessionDirectory(now: now)
        let file = dir.appendingPathComponent("rollout-invalid-timestamp.jsonl")
        try "{\"timestamp\":\"invalid\",\"usage\":{\"input_tokens\":42,\"total_tokens\":42}}\n"
            .write(to: file, atomically: true, encoding: .utf8)

        let summary = CodexUsageReader(root: tempRoot, calendar: calendar).refresh(now: now)
        XCTAssertEqual(summary.todayTokens.input, 42)
        XCTAssertEqual(summary.lastActivity, calendar.startOfDay(for: now))
    }

    func testCacheAndReasoningAreNotCountedOrBilledTwice() throws {
        let line = Data(#"{"usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":20,"reasoning_output_tokens":10,"total_tokens":120}}"#.utf8)
        let tokens = try XCTUnwrap(CodexUsageReader.parseUsage(line)).tokens
        XCTAssertEqual(tokens.input, 20)
        XCTAssertEqual(tokens.cacheRead, 80)
        XCTAssertEqual(tokens.totalTokens, 120)
        XCTAssertEqual(try XCTUnwrap(AgentPricing.estimatedCost(model: "gpt-5", tokens: tokens)),
                       0.000235, accuracy: 0.000000001)
    }

    func testCacheWriteIsAlsoPartOfCodexInput() throws {
        let line = Data(#"{"usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":30,"output_tokens":20}}"#.utf8)
        let tokens = try XCTUnwrap(CodexUsageReader.parseUsage(line)).tokens
        XCTAssertEqual(tokens, AgentTokens(input: 30, cacheWrite: 30, cacheRead: 40, output: 20))
        XCTAssertEqual(tokens.totalTokens, 120)
    }

    func testCumulativeTokenCountOnlyIngestsNewUsage() throws {
        let now = Date()
        let dir = try todaysSessionDirectory(now: now)
        let file = dir.appendingPathComponent("rollout-cumulative.jsonl")
        let timestamp = ISO8601DateFormatter().string(from: now)
        func event(_ input: Int, _ last: Int) -> String {
            "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":0},\"last_token_usage\":{\"input_tokens\":\(last),\"output_tokens\":0}}}}\n"
        }
        try (event(100, 100) + event(100, 100)).write(to: file, atomically: true, encoding: .utf8)
        let reader = CodexUsageReader(root: tempRoot, calendar: calendar)
        XCTAssertEqual(reader.refresh(now: now).todayTokens.input, 100)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((event(140, 40) + event(140, 40)).utf8))
        try handle.close()
        let summary = reader.refresh(now: now)
        XCTAssertEqual(summary.todayTokens.input, 140)
        XCTAssertEqual(summary.latestSessionTokens.input, 140)
    }

    func testRecordsAndLegacyCountersWithSameTotalsDoNotDuplicate() throws {
        let now = Date()
        let dir = try todaysSessionDirectory(now: now)
        let file = dir.appendingPathComponent("rollout-mixed.jsonl")
        let content = """
        {"type":"token_usage_record","payload":{"response_id":"r1","usage":{"input_tokens":100},"thread_token_usage":{"input_tokens":100}}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100},"total_token_usage":{"input_tokens":100}}}}
        {"type":"token_usage_record","payload":{"response_id":"r1","usage":{"input_tokens":100},"thread_token_usage":{"input_tokens":100}}}
        {"type":"token_usage_record","payload":{"response_id":"r2","usage":{"input_tokens":40},"thread_token_usage":{"input_tokens":140}}}

        """
        try content.write(to: file, atomically: true, encoding: .utf8)
        let summary = CodexUsageReader(root: tempRoot).refresh(now: now)
        XCTAssertEqual(summary.todayTokens.input, 140)
    }

    func testReplacingLogsInvalidatesOldTotalsEvenAtSameSize() throws {
        let now = Date()
        let file = try todaysSessionDirectory(now: now).appendingPathComponent("rollout-replaced.jsonl")
        let reader = CodexUsageReader(root: tempRoot)
        try "{\"usage\":{\"input_tokens\":100}}\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(reader.refresh(now: now).todayTokens.input, 100)
        try "{\"usage\":{\"input_tokens\":200}}\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(reader.refresh(now: now).todayTokens.input, 200)
        try "{\"usage\":{\"input_tokens\":20}}\n".write(to: file, atomically: true, encoding: .utf8)
        let replaced = reader.refresh(now: now)
        XCTAssertEqual(replaced.todayTokens.input, 20)
        XCTAssertEqual(replaced.latestSessionTokens.input, 20)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(reader.refresh(now: now).todayTokens.input, 0)
        XCTAssertEqual(reader.trackedFileCount, 0)
    }
}
