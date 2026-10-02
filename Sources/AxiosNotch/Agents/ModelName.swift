import Foundation

/// Turns raw model ids from the logs into short readable names:
/// `claude-sonnet-4-5-20250929` → "Sonnet 4.5", `gpt-5.2-codex` → "GPT-5.2-Codex".
enum ModelName {
    static func display(_ raw: String) -> String {
        let id = raw.lowercased()
        if id.contains("claude") {
            guard let family = ["opus", "sonnet", "haiku"].first(where: { id.contains($0) }) else { return raw }
            // Version digits only: short numbers, never the 8-digit date stamp.
            let version = id.split(separator: "-").compactMap { Int($0) }.filter { $0 < 100 }
            let number = version.map(String.init).joined(separator: ".")
            return number.isEmpty ? family.capitalized : "\(family.capitalized) \(number)"
        }
        // OpenAI-style ids: GPT upper-cased, other words capitalised, numbers untouched.
        return raw.split(separator: "-").map { word -> String in
            let w = String(word)
            if w.lowercased() == "gpt" { return "GPT" }
            return w.first?.isNumber == true ? w : w.capitalized
        }.joined(separator: "-")
    }
}
