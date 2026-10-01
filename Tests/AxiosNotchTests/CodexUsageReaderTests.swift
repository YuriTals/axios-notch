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
        XCTAssertEqual(summary.todayTokens.input, 200)
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
        {"type":"session_meta","payload":{"cwd":"/Users/yuri/Downloads/GBA","cli_version":"0.154.0-alpha.6.2"}}
        {"type":"turn_context","payload":{"cwd":"/Users/yuri/Downloads/GBA","model":"gpt-5.6-terra"}}
        {"type":"token_usage_record","payload":{"usage":{"input_tokens":27890,"cached_input_tokens":21248,"cache_write_input_tokens":0,"output_tokens":127,"reasoning_output_tokens":12,"total_tokens":28017}}}

        """
        try contents.write(to: file, atomically: true, encoding: .utf8)

        let reader = CodexUsageReader(root: tempRoot, calendar: calendar)
        let summary = reader.refresh(now: now)

        XCTAssertEqual(summary.todayTokens.input, 27890)
        XCTAssertEqual(summary.modelSpendToday.first?.name, "gpt-5.6-terra")
        XCTAssertEqual(summary.projectSpendToday.first?.name, "GBA")
        XCTAssertNotNil(summary.estimatedCostToday, "a known model carried forward should still price the usage")
    }

    func testUsesFilePathDayNotLineTimestamp() throws {
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
}
