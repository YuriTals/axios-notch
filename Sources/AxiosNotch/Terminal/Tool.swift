import Foundation

/// A command the user registered to run in a notch tab, like Gemini CLI or Aider.
struct CustomTool: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    /// What to run through the login shell, exactly as typed in a terminal.
    var command: String

    /// Antigravity counts: Claude, Codex, three of these and the terminal make six tiles,
    /// the most that fit the panel (640 pt).
    static let maxCount = 3
    static let maxNameLength = 14

    /// Google's Antigravity CLI (`agy`, the successor of Gemini CLI) ships with the notch
    /// next to Claude, Codex and the terminal. A fixed id keeps its tabs and saved
    /// sessions stable, and it can still be removed or re-added like any other.
    static let antigravityID = "antigravity"
    static let defaultAntigravity = CustomTool(id: antigravityID, name: "Antigravity", command: "agy")
    /// What a fresh install starts with.
    static let defaults: [CustomTool] = [defaultAntigravity]

    /// The untouched Gemini entry earlier versions shipped as the default.
    static let legacyGeminiID = "gemini"
    static let legacyGemini = CustomTool(id: legacyGeminiID, name: "Gemini", command: "gemini")

    /// Swaps the old untouched Gemini default for Antigravity, keeping its place in the
    /// list. A Gemini entry the user edited (another command, say) is theirs: left alone.
    static func migrated(_ tools: [CustomTool]) -> [CustomTool] {
        guard tools.contains(legacyGemini) else { return tools }
        let hasAntigravity = tools.contains { $0.id == antigravityID }
        return tools.compactMap { tool in
            guard tool == legacyGemini else { return tool }
            return hasAntigravity ? nil : defaultAntigravity
        }
    }

    /// The id a saved tab of a migrated tool should now point at.
    static func migratedID(_ id: String, in tools: [CustomTool]) -> String {
        id == legacyGeminiID && !tools.contains(where: { $0.id == legacyGeminiID }) ? antigravityID : id
    }

    /// Suggestions offered with one click, with how to install each.
    static let presets: [(name: String, command: String, install: String)] = [
        ("Antigravity", "agy", "curl -fsSL https://antigravity.google/cli/install.sh | bash"),
        ("Gemini", "gemini", "npm install -g @google/gemini-cli"),
        ("Aider", "aider", "python -m pip install aider-install && aider-install"),
        ("OpenCode", "opencode", "npm install -g opencode-ai"),
        ("Goose", "goose session", "brew install block-goose-cli"),
    ]

    /// How to install the program a command starts, when we know it.
    static func installHint(for command: String) -> String? {
        let word = firstWord(of: command)
        return presets.first { firstWord(of: $0.command) == word }?.install
    }

    /// The program name when the command is a plain invocation; nil for anything
    /// with shell syntax (`a; b`, pipes, redirects, quotes), which we do not inspect.
    static func firstWord(of command: String) -> String {
        command.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
    }

    static func isPlainProgram(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isLetter || $0.isNumber || "._-/".contains($0) }
    }

    /// A tool needs a visible name and a command to run.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func normalized() -> CustomTool {
        var copy = self
        copy.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        copy.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

/// What a terminal tab runs: a plain shell, one of the agents the app knows in
/// depth (Claude, Codex), or a command the user registered.
enum Tool: Hashable {
    case shell
    case agent(AgentProvider)
    case custom(String)

    /// Stable text form, used as a dictionary key and when saving tabs.
    var id: String {
        switch self {
        case .shell: return "shell"
        case .agent(let provider): return provider.rawValue
        case .custom(let id): return "custom:\(id)"
        }
    }

    init?(id: String) {
        if id == "shell" { self = .shell }
        else if let provider = AgentProvider(rawValue: id) { self = .agent(provider) }
        else if id.hasPrefix("custom:"), id.count > 7 { self = .custom(String(id.dropFirst(7))) }
        else { return nil }
    }

    /// Claude or Codex — the tools with usage limits, approval prompts and answer copying.
    var agent: AgentProvider? {
        if case .agent(let provider) = self { return provider }
        return nil
    }

    var isShell: Bool { self == .shell }
    var isCustom: Bool { if case .custom = self { return true } else { return false } }

    /// Name shown in tabs and titles.
    func displayName(customTools: [CustomTool] = AppSettings.shared.customTools) -> String {
        switch self {
        case .shell: return "Terminal"
        case .agent(let provider): return provider.displayName
        case .custom(let id): return customTools.first { $0.id == id }?.name ?? tr("Ferramenta", "Tool")
        }
    }

    /// The tools shown in the picker and the drop strip, in order.
    static func all(customTools: [CustomTool] = AppSettings.shared.customTools) -> [Tool] {
        AgentProvider.allCases.map(Tool.agent) + customTools.map { .custom($0.id) } + [.shell]
    }
}
