import XCTest
@testable import AxiosNotch

final class CostAvailabilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    private func event(_ model: String?, input: Int = 1_000_000, daysAgo: Double = 0,
                       id: String? = nil, source: URL? = nil) -> AgentUsageEvent {
        AgentUsageEvent(date: now.addingTimeInterval(-daysAgo * 86400), model: model,
                        project: "project", tokens: AgentTokens(input: input), id: id, source: source)
    }

    func testUnpricedModelKeepsTokensAndUnavailableCostInEveryBucket() throws {
        let aggregator = AgentUsageAggregator()
        aggregator.ingest(event("gpt-6.1-sol", input: 1_100_000))
        let result = aggregator.snapshot(now: now)
        XCTAssertEqual(result.todayTokens.totalTokens, 1_100_000)
        XCTAssertEqual(result.week.tokens.totalTokens, 1_100_000)
        XCTAssertEqual(result.fiveHourBlock?.tokens.totalTokens, 1_100_000)
        XCTAssertNil(result.estimatedCostToday)
        XCTAssertNil(result.week.cost)
        XCTAssertNil(result.fiveHourBlock?.cost)
        XCTAssertNil(result.totalCostInHistory)
        XCTAssertNil(result.dailyHistory.first?.cost)
        XCTAssertNil(result.modelSpendToday.first?.cost)
        XCTAssertNil(result.projectSpendToday.first?.cost)
        XCTAssertTrue(result.hourlySpendToday.allSatisfy { $0 == nil })
        XCTAssertTrue(result.weekDailyCost.allSatisfy { $0 == nil })
        XCTAssertTrue(result.todayCostEstimate.hasUnpricedUsage)
        XCTAssertFalse(result.todayCostEstimate.isPartial)
        XCTAssertEqual(result.activeDaysInHistory, 1, "usage remains an active day without a tariff")
        XCTAssertNil(result.busiestDay, "there is no priced day to rank by cost")
    }

    func testMissingAndSyntheticModelAlsoLeaveCostUnavailable() {
        for model in [nil, "<synthetic>"] as [String?] {
            let aggregator = AgentUsageAggregator()
            aggregator.ingest(event(model))
            let result = aggregator.snapshot(now: now)
            XCTAssertEqual(result.todayTokens.totalTokens, 1_000_000)
            XCTAssertNil(result.estimatedCostToday)
            XCTAssertTrue(result.week.costEstimate.hasUnpricedUsage)
        }
    }

    func testMixedModelsKeepKnownSubtotalAndMarkItPartial() throws {
        let aggregator = AgentUsageAggregator()
        aggregator.ingest(event("claude-sonnet-4"))
        aggregator.ingest(event("gpt-6.1-sol", input: 2_000_000))
        let result = aggregator.snapshot(now: now)
        XCTAssertEqual(result.todayTokens.totalTokens, 3_000_000)
        XCTAssertEqual(result.estimatedCostToday, 3)
        XCTAssertEqual(result.week.cost, 3)
        XCTAssertEqual(result.fiveHourBlock?.cost, 3)
        XCTAssertEqual(result.totalCostInHistory, 3)
        XCTAssertTrue(result.todayCostEstimate.isPartial)
        XCTAssertTrue(result.week.costEstimate.isPartial)
        XCTAssertTrue(try XCTUnwrap(result.fiveHourBlock).costEstimate.isPartial)
        XCTAssertTrue(result.historyCostEstimate.isPartial)
        XCTAssertTrue(try XCTUnwrap(result.dailyHistory.first).costEstimate.isPartial)
        XCTAssertTrue(try XCTUnwrap(result.projectSpendToday.first).costEstimate.isPartial)
        let hour = Calendar.current.component(.hour, from: now)
        XCTAssertTrue(result.hourlyCostEstimatesToday[hour].isPartial)
        XCTAssertTrue(try XCTUnwrap(result.weekDailyCostEstimates.last).isPartial)
        XCTAssertFalse(AgentModelUsage.usesCost(result.weekModels))
        XCTAssertEqual(result.weekModels.first?.name, "gpt-6.1-sol", "rank by tokens when pricing is incomplete")
    }

    func testUnpricedOldUsageDoesNotMakeCurrentWindowsPartial() {
        let aggregator = AgentUsageAggregator()
        aggregator.ingest(event("gpt-6.1-sol", daysAgo: 10))
        aggregator.ingest(event("claude-sonnet-4"))
        let result = aggregator.snapshot(now: now)
        XCTAssertEqual(result.estimatedCostToday, 3)
        XCTAssertTrue(result.todayCostEstimate.isComplete)
        XCTAssertTrue(result.week.costEstimate.isComplete)
        XCTAssertEqual(result.fiveHourBlock?.cost, 3)
        XCTAssertTrue(result.historyCostEstimate.isPartial)
        XCTAssertTrue(AgentModelUsage.usesCost(result.weekModels))
    }

    func testReplacingResponseRecomputesAvailabilityInBothDirections() {
        let aggregator = AgentUsageAggregator()
        aggregator.ingest(event("gpt-6.1-sol", id: "response"))
        XCTAssertNil(aggregator.snapshot(now: now).estimatedCostToday)
        aggregator.ingest(event("claude-sonnet-4", id: "response"))
        let priced = aggregator.snapshot(now: now)
        XCTAssertEqual(priced.todayTokens.totalTokens, 1_000_000)
        XCTAssertEqual(priced.estimatedCostToday, 3)
        XCTAssertTrue(priced.todayCostEstimate.isComplete)
        aggregator.ingest(event("gpt-6.1-sol", id: "response"))
        XCTAssertNil(aggregator.snapshot(now: now).estimatedCostToday)
    }

    func testRemovingUnpricedLogRestoresCompleteSubtotal() {
        let aggregator = AgentUsageAggregator()
        let known = URL(fileURLWithPath: "/tmp/known.jsonl")
        let unknown = URL(fileURLWithPath: "/tmp/unknown.jsonl")
        aggregator.ingest(event("claude-sonnet-4", source: known))
        aggregator.ingest(event("gpt-6.1-sol", source: unknown))
        XCTAssertTrue(aggregator.snapshot(now: now).todayCostEstimate.isPartial)
        aggregator.removeEvents(from: unknown)
        let result = aggregator.snapshot(now: now)
        XCTAssertEqual(result.estimatedCostToday, 3)
        XCTAssertTrue(result.todayCostEstimate.isComplete)
        XCTAssertTrue(result.historyCostEstimate.isComplete)
    }

    func testUnpricedZeroTokenEventDoesNotMakeKnownUsagePartial() {
        let aggregator = AgentUsageAggregator()
        aggregator.ingest(event("gpt-6.1-sol", input: 0))
        aggregator.ingest(event("claude-sonnet-4", input: 1))
        let result = aggregator.snapshot(now: now)
        XCTAssertTrue(result.todayCostEstimate.isComplete)
        XCTAssertEqual(result.estimatedCostToday ?? -1, 0.000003, accuracy: 1e-12)
    }

    func testCompleteModelCostsStillRankBySpend() {
        let aggregator = AgentUsageAggregator()
        aggregator.ingest(event("claude-sonnet-4", input: 2_000_000))
        aggregator.ingest(event("claude-opus-4", input: 1_000_000))
        let result = aggregator.snapshot(now: now)
        XCTAssertTrue(AgentModelUsage.usesCost(result.weekModels))
        XCTAssertEqual(result.weekModels.map(\.name), ["claude-opus-4", "claude-sonnet-4"])
    }

    func testCostMessagesDistinguishUnavailablePartialAndComplete() {
        var unavailable = AgentUsageWindow(tokens: AgentTokens(input: 1_100_000))
        unavailable.costEstimate.add(nil, tokens: 1_100_000)
        var partial = AgentUsageWindow(tokens: AgentTokens(input: 2_000_000))
        partial.costEstimate.add(3, tokens: 1_000_000)
        partial.costEstimate.add(nil, tokens: 1_000_000)
        var complete = AgentUsageWindow(tokens: AgentTokens(input: 1))
        complete.costEstimate.add(0.000003, tokens: 1)
        withLanguage(.pt) {
            XCTAssertEqual(UsageFormat.usageFootnote(unavailable), "1.1M tokens · custo indisponível")
            XCTAssertEqual(UsageFormat.usageFootnote(partial), "2.0M tokens · $3.00 (parcial)")
            XCTAssertEqual(UsageFormat.usageFootnote(complete), "1 tokens · $0.00")
        }
        withLanguage(.en) {
            XCTAssertEqual(UsageFormat.usageFootnote(unavailable), "1.1M tokens · cost unavailable")
            XCTAssertEqual(UsageFormat.usageFootnote(partial), "2.0M tokens · $3.00 (partial)")
        }
    }

    func testReadersPropagateAvailabilityAndPartialCostFromLogFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("axios-cost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let timestamp = ISO8601DateFormatter().string(from: now)
        let claudeRoot = root.appendingPathComponent("claude")
        let codexRoot = root.appendingPathComponent("codex")
        for directory in [claudeRoot, codexRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"id":"a","model":"unpriced-model","usage":{"input_tokens":100}}}
        {"type":"assistant","timestamp":"\(timestamp)","message":{"id":"b","model":"claude-sonnet-4","usage":{"input_tokens":1000000}}}

        """.write(to: claudeRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        try """
        {"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}
        {"type":"token_usage_record","timestamp":"\(timestamp)","payload":{"usage":{"input_tokens":1100000}}}

        """.write(to: codexRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        let claude = ClaudeUsageReader(root: claudeRoot).refresh(now: now)
        XCTAssertEqual(claude.estimatedCostToday, 3)
        XCTAssertTrue(claude.todayCostEstimate.isPartial)
        XCTAssertTrue(claude.week.costEstimate.isPartial)
        XCTAssertTrue(claude.historyCostEstimate.isPartial)
        let codex = CodexUsageReader(root: codexRoot).refresh(now: now)
        XCTAssertEqual(codex.todayTokens.totalTokens, 1_100_000)
        XCTAssertNil(codex.estimatedCostToday)
        XCTAssertNil(codex.week.cost)
        XCTAssertTrue(codex.todayCostEstimate.hasUnpricedUsage)
    }
}
