import XCTest
@testable import AxiosNotch

final class ClaudeUsageReaderTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("axios-notch-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testAggregatesTokensFromAssistantLines() throws {
        let now = Date()
        let session = tempRoot.appendingPathComponent("my-project", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let file = session.appendingPathComponent("session.jsonl")

        let timestamp = ClaudeUsageReaderTests.iso(now)
        let contents = """
        {"type":"user","message":{"role":"user"}}
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":10,"cache_read_input_tokens":5,"output_tokens":20}}}
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4","role":"assistant","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}

        """
        try contents.write(to: file, atomically: true, encoding: .utf8)

        let reader = ClaudeUsageReader(root: tempRoot)
        let summary = reader.refresh(now: now)

        XCTAssertTrue(summary.hasAnySession)
        XCTAssertEqual(summary.todayTokens.input, 150)
        XCTAssertEqual(summary.todayTokens.output, 30)
        XCTAssertEqual(summary.todayTokens.cacheWrite, 10)
        XCTAssertEqual(summary.todayTokens.cacheRead, 5)
        XCTAssertEqual(summary.latestSessionTokens.totalTokens, summary.todayTokens.totalTokens)
    }

    func testOnlyReadsAppendedBytesOnSecondRefresh() throws {
        let now = Date()
        let session = tempRoot.appendingPathComponent("my-project", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let file = session.appendingPathComponent("session.jsonl")

        let timestamp = ClaudeUsageReaderTests.iso(now)
        let firstLine = """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4","usage":{"input_tokens":100,"output_tokens":10}}}

        """
        try firstLine.write(to: file, atomically: true, encoding: .utf8)

        let reader = ClaudeUsageReader(root: tempRoot)
        let first = reader.refresh(now: now)
        XCTAssertEqual(first.todayTokens.totalTokens, 110)

        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        let secondLine = """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4","usage":{"input_tokens":40,"output_tokens":4}}}

        """
        handle.write(secondLine.data(using: .utf8)!)
        try handle.close()

        let second = reader.refresh(now: now)
        XCTAssertEqual(second.todayTokens.totalTokens, 154)
    }

    func testIgnoresUnterminatedTrailingLine() throws {
        let now = Date()
        let session = tempRoot.appendingPathComponent("my-project", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let file = session.appendingPathComponent("session.jsonl")

        let timestamp = ClaudeUsageReaderTests.iso(now)
        let partial = """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4","usage":{"input_tokens":100,"output_tokens":10}}}
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4","usage":{"input_tokens":999
        """
        try partial.write(to: file, atomically: true, encoding: .utf8)

        let reader = ClaudeUsageReader(root: tempRoot)
        let summary = reader.refresh(now: now)
        XCTAssertEqual(summary.todayTokens.totalTokens, 110, "the unterminated second line should not be parsed yet")
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
