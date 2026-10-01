import XCTest
@testable import AxiosNotch

final class RateLimitParserTests: XCTestCase {
    private func json(_ text: String) -> Any { try! JSONSerialization.jsonObject(with: Data(text.utf8)) }

    func testClaudeUsageReadsPercentAndResetForBothWindows() {
        let limits = RateLimitParser.claude(json("""
        {"five_hour":{"utilization":5.0,"resets_at":"2026-10-02T01:59:59.907933+00:00"},
         "seven_day":{"utilization":43.0,"resets_at":"2026-10-05T09:59:59.907954+00:00"},
         "seven_day_opus":null}
        """), plan: "pro")

        XCTAssertEqual(limits?.fiveHour?.percent, 5)
        XCTAssertEqual(limits?.weekly?.percent, 43)
        XCTAssertNotNil(limits?.weekly?.resetsAt)
        XCTAssertEqual(limits?.planLabel, "pro")
    }

    func testClaudeUsageWithoutKnownWindowsIsRejected() {
        XCTAssertNil(RateLimitParser.claude(json(#"{"something":1}"#), plan: nil))
    }

    func testCodexNestedWindowsAreSlottedByLength() {
        // Longer window listed first on purpose.
        let limits = RateLimitParser.codex(json("""
        {"plan_type":"plus","rate_limit":{
          "primary_window":{"used_percent":91,"limit_window_seconds":604800,"reset_at":1789892506},
          "secondary_window":{"used_percent":4,"limit_window_seconds":18000,"reset_after_seconds":3600}}}
        """))

        XCTAssertEqual(limits?.fiveHour?.percent, 4)
        XCTAssertEqual(limits?.weekly?.percent, 91)
        XCTAssertEqual(limits?.weekly?.resetsAt, Date(timeIntervalSince1970: 1789892506))
        XCTAssertEqual(limits?.planLabel, "plus")
    }

    func testCodexFlatPrimarySecondaryShape() {
        let limits = RateLimitParser.codex(json("""
        {"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1789455655},
         "secondary":{"used_percent":60,"window_minutes":10080,"resets_at":1789892506}}
        """))

        XCTAssertEqual(limits?.fiveHour?.percent, 12.5)
        XCTAssertEqual(limits?.weekly?.percent, 60)
    }
}
