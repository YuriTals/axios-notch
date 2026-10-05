import XCTest
@testable import AxiosNotch

final class AntigravityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_043_200)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func bucket(_ id: String, _ window: String, _ fraction: Double, reset: Date? = nil) -> [String: Any] {
        ["bucketId": id, "window": window, "remainingFraction": fraction,
         "resetTime": ISO8601DateFormatter().string(from: reset ?? now.addingTimeInterval(3600))]
    }
    private func quota() -> [String: Any] {
        ["groups": [
            ["displayName": "Gemini Models", "buckets": [bucket("gemini-5h", "5h", 0.8), bucket("gemini-weekly", "weekly", 0.65)]],
            ["displayName": "Claude and GPT models", "buckets": [bucket("3p-5h", "5h", 0.1), bucket("3p-weekly", "weekly", 1)]]
        ]]
    }

    func testIndependentFamilyQuotasConvertRemainingToUsed() throws {
        let reading = try XCTUnwrap(RateLimitParser.antigravity(quota(), now: now))
        let groups = try XCTUnwrap(reading.quotaGroups)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(try XCTUnwrap(groups[0].fiveHour?.percent), 20, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(groups[0].weekly?.percent), 35, accuracy: 0.0001)
        XCTAssertEqual(groups[1].fiveHour?.percent, 90)
        XCTAssertEqual(groups[1].weekly?.percent, 0)
        XCTAssertNil(reading.fiveHour, "do not mix independent families")
        XCTAssertEqual(reading.pickerLimit?.percent, 90)
        XCTAssertEqual(reading.mostUsedLimit(in: .fiveHour), groups[1].fiveHour)
        XCTAssertEqual(reading.mostUsedLimit(in: .weekly), groups[0].weekly)
        XCTAssertNotNil(reading.valid(at: now))
    }

    func testInvalidExpiredDisabledAndUnknownWindowsAreNotInvented() {
        let invalid: [[String: Any]] = [bucket("past", "5h", 0.3, reset: now), bucket("negative", "5h", -1),
            bucket("over", "weekly", 2), bucket("future", "daily", 0.5), ["window": "5h", "remainingFraction": 0.4],
            bucket("disabled", "5h", 0.5).merging(["disabled": true]) { _, b in b },
            bucket("boolean", "5h", 0.5).merging(["remainingFraction": true]) { _, b in b }]
        for value in invalid {
            XCTAssertNil(RateLimitParser.antigravity(["groups": [["displayName": "Test", "buckets": [value]]]], now: now))
        }
        XCTAssertNil(RateLimitParser.antigravity([:], now: now))
    }

    func testQuotaCacheExpiresWindowsIndependentlyAndDecodesOldReadings() throws {
        let reading = AgentRateLimits(quotaGroups: [
            AgentQuotaGroup(id: "gemini", label: "Gemini", fiveHour: AgentLimit(percent: 50, resetsAt: now.addingTimeInterval(60)),
                            weekly: AgentLimit(percent: 10, resetsAt: now.addingTimeInterval(7200)))
        ], fetchedAt: now)
        let data = try JSONEncoder().encode(reading)
        let decoded = try JSONDecoder().decode(AgentRateLimits.self, from: data)
        XCTAssertEqual(decoded, reading)
        XCTAssertNil(decoded.valid(at: now.addingTimeInterval(61))?.quotaGroups?.first?.fiveHour)
        XCTAssertEqual(decoded.valid(at: now.addingTimeInterval(61))?.quotaGroups?.first?.weekly?.percent, 10)
        XCTAssertNil(decoded.valid(at: now.addingTimeInterval(7200)))
        XCTAssertNil(decoded.valid(at: now.addingTimeInterval(6 * 3600)))
        let old = Data("{\"fetchedAt\":0,\"modelLimits\":[]}".utf8)
        XCTAssertNil(try JSONDecoder().decode(AgentRateLimits.self, from: old).quotaGroups)
    }

    func testCredentialsSupportKeychainEncodingAndFileWithoutRetainingRefreshToken() throws {
        let raw = "{\"token\":{\"access_token\":\"fake-access\",\"refresh_token\":\"discard\",\"expiry\":\"2026-10-03T14:57:51.447348-03:00\"},\"email\":\"discard\"}"
        let plain = try XCTUnwrap(AntigravityCredentials.parse(raw))
        let encoded = try XCTUnwrap(AntigravityCredentials.parse("go-keyring-base64:" + Data(raw.utf8).base64EncodedString()))
        XCTAssertEqual(plain.accessToken, "fake-access")
        XCTAssertEqual(encoded.expiresAt, plain.expiresAt)
        XCTAssertNil(AntigravityCredentials.parse("go-keyring-base64:bad"))
        XCTAssertNil(AntigravityCredentials.parse("{\"token\":{\"access_token\":\"fake\"}}"))
    }

    private func root() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    private func row(step: Int = 1, input: Int = 100, cache: Int = 200, output: Int = 50, date: Date? = nil, status: String = "DONE") throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["step_index": step, "source": "MODEL", "type": "PLANNER_RESPONSE",
            "status": status, "created_at": ISO8601DateFormatter().string(from: date ?? now),
            "input_tokens": input, "cache_read_tokens": cache, "output_tokens": output, "thinking_tokens": 30,
            "content": "must not retain"])
        data.append(10)
        return data
    }

    func testTranscriptCacheIsDisjointAndThinkingIsInsideOutput() throws {
        let file = URL(fileURLWithPath: "/test/transcript_full.jsonl")
        let entry = try XCTUnwrap(AntigravityUsageReader.parseUsage(try row(), source: file))
        XCTAssertEqual(entry.event.tokens.totalTokens, 350)
        XCTAssertEqual(entry.event.tokens.cacheRead, 200)
        XCTAssertEqual(entry.event.tokens.reasoning, 30)
        XCTAssertNil(entry.event.model, "never apply today's selected model to historical responses")
        XCTAssertNil(AntigravityUsageReader.parseUsage(try row(status: "ACTIVE"), source: file))
        XCTAssertNil(AntigravityUsageReader.parseUsage(try row(input: -1), source: file))
    }

    func testMirrorDuplicateStepAndIncrementalRefreshDoNotDoubleCount() throws {
        let dir = try root(), logs = dir.appendingPathComponent("conversation/.system_generated/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let file = logs.appendingPathComponent("transcript_full.jsonl")
        let data = try row()
        try (data + data).write(to: file)
        try data.write(to: logs.appendingPathComponent("transcript.jsonl"))
        let reader = AntigravityUsageReader(root: dir, calendar: calendar)
        let first = reader.refresh(now: now.addingTimeInterval(1))
        XCTAssertEqual(first.todayTokens.totalTokens, 350)
        XCTAssertEqual(reader.refresh(now: now.addingTimeInterval(2)).todayTokens.totalTokens, 350)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: row(step: 2))
        try handle.close()
        let updated = reader.refresh(now: now.addingTimeInterval(3))
        XCTAssertEqual(updated.todayTokens.totalTokens, 700)
        XCTAssertEqual(updated.latestSessionTokens.totalTokens, 700)
        XCTAssertNil(updated.estimatedCostToday)
        XCTAssertTrue(updated.todayCostEstimate.hasUnpricedUsage)
        XCTAssertTrue(updated.weekModels.isEmpty)
    }

    func testRewritesAndRemovalInvalidateOldUsage() throws {
        let dir = try root(), file = dir.appendingPathComponent("transcript_full.jsonl")
        try row().write(to: file)
        let reader = AntigravityUsageReader(root: dir, calendar: calendar)
        XCTAssertEqual(reader.refresh(now: now).todayTokens.totalTokens, 350)
        try row(input: 10, cache: 0, output: 1).write(to: file)
        XCTAssertEqual(reader.refresh(now: now.addingTimeInterval(1)).todayTokens.totalTokens, 11)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(reader.refresh(now: now.addingTimeInterval(2)).todayTokens.totalTokens, 0)
    }

    func testResumedConversationUsesEventDateInsteadOfCreationDate() throws {
        let dir = try root(), file = dir.appendingPathComponent("transcript_full.jsonl")
        try (row(date: now.addingTimeInterval(-2 * 86400)) + row(step: 2)).write(to: file)
        let summary = AntigravityUsageReader(root: dir, calendar: calendar).refresh(now: now.addingTimeInterval(1))
        XCTAssertEqual(summary.todayTokens.totalTokens, 350)
        XCTAssertEqual(summary.week.tokens.totalTokens, 700)
    }

    func testAntigravityRoutesToUsageAndKeepsTerminalBehaviorAndSavedIDs() {
        XCTAssertEqual(Tool.antigravity.usageProvider, .antigravity)
        XCTAssertNil(Tool.antigravity.agent)
        XCTAssertTrue(Tool.antigravity.isOtherCLI)
        XCTAssertEqual(AgentProvider.antigravity.tool, .antigravity)
        XCTAssertEqual(Tool(id: "antigravity"), .antigravity)
        XCTAssertEqual(Tool(id: "custom:gemini"), .antigravity)
        XCTAssertEqual(Tool.all(customTools: []), [.agent(.claude), .agent(.codex), .antigravity, .shell])
        XCTAssertEqual(AgentDirectories.configuration(for: .antigravity, environment: ["CODEX_HOME": "/other"], home: URL(fileURLWithPath: "/home")), URL(fileURLWithPath: "/home/.gemini/antigravity-cli", isDirectory: true))
    }
}
