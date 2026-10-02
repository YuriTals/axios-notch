import XCTest
@testable import AxiosNotch

final class ModelUsageTests: XCTestCase {
    func testClaudeModelIdsBecomeShortNames() {
        XCTAssertEqual(ModelName.display("claude-sonnet-4-5-20250929"), "Sonnet 4.5")
        XCTAssertEqual(ModelName.display("claude-opus-4-20250514"), "Opus 4")
        XCTAssertEqual(ModelName.display("claude-3-5-haiku-20241022"), "Haiku 3.5")
        XCTAssertEqual(ModelName.display("claude-sonnet-4"), "Sonnet 4")
    }

    func testOpenAIModelIdsAreReadable() {
        XCTAssertEqual(ModelName.display("gpt-5.2-codex"), "GPT-5.2-Codex")
        XCTAssertEqual(ModelName.display("gpt-5"), "GPT-5")
    }

    func testWeekModelsSplitUsageAndIgnoreOldOrUnnamedEvents() {
        let now = Date()
        let aggregator = AgentUsageAggregator()
        func event(_ daysAgo: Double, _ model: String?, _ output: Int) -> AgentUsageEvent {
            AgentUsageEvent(date: now.addingTimeInterval(-daysAgo * 86_400), model: model, project: nil, tokens: AgentTokens(output: output))
        }
        aggregator.ingest(event(1, "claude-sonnet-4", 1_000_000))   // priced
        aggregator.ingest(event(2, "claude-opus-4", 1_000_000))
        aggregator.ingest(event(3, "claude-opus-4", 1_000_000))
        aggregator.ingest(event(10, "claude-haiku-4", 5_000_000))   // older than a week
        aggregator.ingest(event(1, nil, 7_000_000))                 // no model
        aggregator.ingest(event(1, "<synthetic>", 7_000_000))

        let models = aggregator.snapshot(now: now).weekModels
        XCTAssertEqual(models.map(\.name), ["claude-opus-4", "claude-sonnet-4"])   // opus costs more, two calls
        XCTAssertEqual(models.first?.tokens, 2_000_000)
    }

    func testClaudeUsagePerModelCapsOnlyKeepTouchedOnes() {
        let json = try! JSONSerialization.jsonObject(with: Data("""
        {"five_hour":{"utilization":5,"resets_at":"2026-10-02T01:59:59+00:00"},
         "seven_day":{"utilization":43,"resets_at":"2026-10-05T09:59:59+00:00"},
         "seven_day_opus":{"utilization":40,"resets_at":"2026-10-05T09:59:59+00:00"},
         "seven_day_sonnet":{"utilization":0,"resets_at":"2026-10-05T09:59:59+00:00"},
         "seven_day_cowork":null}
        """.utf8))
        let limits = RateLimitParser.claude(json, plan: "max")

        XCTAssertEqual(limits?.modelLimits.map(\.label), ["Opus"])
        XCTAssertEqual(limits?.modelLimits.first?.limit.percent, 40)
    }
}
