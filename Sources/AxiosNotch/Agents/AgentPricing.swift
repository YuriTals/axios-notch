import Foundation

/// Best-effort $ estimate for token usage, keyed by a substring of the
/// model name (model names drift — e.g. "claude-fable-5", "<synthetic>",
/// "gpt-5.6-terra" — so this matches loosely instead of exact strings).
/// When no family matches, cost is simply not shown; tokens still are.
enum AgentPricing {
    private struct Rate {
        let inputPer1M: Double
        let outputPer1M: Double
        let cacheReadPer1M: Double
    }

    private static let rates: [(match: String, rate: Rate)] = [
        ("opus", Rate(inputPer1M: 15, outputPer1M: 75, cacheReadPer1M: 1.5)),
        ("sonnet", Rate(inputPer1M: 3, outputPer1M: 15, cacheReadPer1M: 0.3)),
        ("haiku", Rate(inputPer1M: 0.8, outputPer1M: 4, cacheReadPer1M: 0.08)),
        ("fable", Rate(inputPer1M: 3, outputPer1M: 15, cacheReadPer1M: 0.3)),
        ("gpt-5", Rate(inputPer1M: 1.25, outputPer1M: 10, cacheReadPer1M: 0.125)),
        ("o3", Rate(inputPer1M: 2, outputPer1M: 8, cacheReadPer1M: 0.5)),
        ("o4", Rate(inputPer1M: 2, outputPer1M: 8, cacheReadPer1M: 0.5)),
    ]

    /// Estimated cost for a single model's tokens, or nil if the model
    /// doesn't match any known family.
    static func estimatedCost(model: String, tokens: AgentTokens) -> Double? {
        let needle = model.lowercased()
        guard let rate = rates.first(where: { needle.contains($0.match) })?.rate else { return nil }

        let inputCost = Double(tokens.input + tokens.cacheWrite) / 1_000_000 * rate.inputPer1M
        let cacheReadCost = Double(tokens.cacheRead) / 1_000_000 * rate.cacheReadPer1M
        let outputCost = Double(tokens.output + tokens.reasoning) / 1_000_000 * rate.outputPer1M
        return inputCost + cacheReadCost + outputCost
    }
}
