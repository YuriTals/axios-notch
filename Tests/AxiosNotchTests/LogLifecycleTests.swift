import XCTest
@testable import AxiosNotch

final class LogLifecycleTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("axios-logs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.resolvingSymlinksInPath()
    }

    func testClaudeReplacementRemovesResponsesAbsentFromNewLog() throws {
        let root = try directory(), now = Date()
        let file = root.appendingPathComponent("session.jsonl")
        let timestamp = ISO8601DateFormatter().string(from: now)
        func line(_ id: String, _ input: Int) -> String {
            "{\"type\":\"assistant\",\"timestamp\":\"\(timestamp)\",\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input)}}}\n"
        }
        try (line("a", 100) + line("b", 30)).write(to: file, atomically: true, encoding: .utf8)
        let reader = ClaudeUsageReader(root: root)
        XCTAssertEqual(reader.refresh(now: now).todayTokens.input, 130)
        try line("a", 20).write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(reader.refresh(now: now).todayTokens.input, 20)
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(reader.refresh(now: now).lastActivity)
        XCTAssertEqual(reader.trackedFileCount, 0)
    }

    func testTailReaderHandlesPartialLinesAndInPlaceTruncation() throws {
        let file = try directory().appendingPathComponent("a.jsonl")
        try Data("first\npar".utf8).write(to: file)
        let reader = JSONLTailReader()
        XCTAssertEqual(reader.read(in: file)?.lines, [Data("first".utf8)])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tial\n".utf8))
        let appended = try XCTUnwrap(reader.read(in: file))
        XCTAssertFalse(appended.wasReset)
        XCTAssertEqual(appended.lines, [Data("partial".utf8)])
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data("new\n".utf8))
        try handle.close()
        let replaced = try XCTUnwrap(reader.read(in: file))
        XCTAssertTrue(replaced.wasReset)
        XCTAssertEqual(replaced.lines, [Data("new".utf8)])
        reader.retainFiles([])
        XCTAssertEqual(reader.trackedFileCount, 0)
    }

    func testIndexAvoidsRepeatedTraversalAndDiscoversNewLogs() throws {
        let root = try directory(), now = Date()
        let file = root.appendingPathComponent("a.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let index = SessionFileIndex(root: root, calendar: .current, scanInterval: 30)
        XCTAssertEqual(index.files(now: now), [file])
        for offset in stride(from: 5.0, through: 25.0, by: 5) {
            XCTAssertEqual(index.files(now: now.addingTimeInterval(offset)), [file])
        }
        XCTAssertEqual(index.scanCount, 1)
        let second = root.appendingPathComponent("b.jsonl")
        try Data("{}\n".utf8).write(to: second)
        XCTAssertEqual(Set(index.files(now: now.addingTimeInterval(30))), Set([file, second]))
        XCTAssertEqual(index.scanCount, 2)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(index.files(now: now.addingTimeInterval(31)), [second])
        XCTAssertTrue(index.files(now: now.addingTimeInterval(92 * 86400)).isEmpty)
    }

    func testManyLogsKeepTotalsWhileAvoidingFullDirectoryScans() throws {
        let root = try directory(), now = Date()
        let timestamp = ISO8601DateFormatter().string(from: now)
        for index in 0..<500 {
            let folder = root.appendingPathComponent("project\(index % 20)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let line = "{\"type\":\"assistant\",\"timestamp\":\"\(timestamp)\",\"message\":{\"id\":\"\(index)\",\"usage\":{\"input_tokens\":10}}}\n"
            try Data(line.utf8).write(to: folder.appendingPathComponent("\(index).jsonl"))
        }
        let reader = ClaudeUsageReader(root: root)
        let start = Date()
        XCTAssertEqual(reader.refresh(now: now).todayTokens.input, 5000)
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        for offset in [5.0, 10, 15, 20, 25] {
            XCTAssertEqual(reader.refresh(now: now.addingTimeInterval(offset)).todayTokens.input, 5000)
        }
        print("500 synthetic logs: initial \(cold)s; five incremental polls \(Date().timeIntervalSince(warmStart))s")
        XCTAssertEqual(reader.trackedFileCount, 500)
        XCTAssertEqual(reader.refresh(now: now.addingTimeInterval(92 * 86400)).todayTokens.input, 0)
        XCTAssertEqual(reader.trackedFileCount, 0)
    }
}
