import Foundation

/// A command the user registered to run in a notch tab, like Aider or OpenCode.
struct CustomTool: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    /// What to run through the login shell, exactly as typed in a terminal.
    var command: String

    /// Claude, Codex, Antigravity and the terminal are built in; two more commands fit in
    /// the panel (six tiles at 640 pt is the most it holds).
    static let maxCount = 2
    static let maxNameLength = 14

    /// Uppercasing one grapheme can produce several (ß → SS).
    static func initial(for name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "?"
    }

    /// What a fresh install starts with: nothing extra.
    static let defaults: [CustomTool] = []

    /// Suggestions offered with one click.
    static let presets: [(name: String, command: String)] = [
        ("Aider", "aider"),
        ("OpenCode", "opencode"),
        ("Goose", "goose session"),
    ]

    /// How to install a program, by the command that starts it. Antigravity (`agy`) is
    /// built in and listed here only so a missing install can be explained.
    static let installHints: [String: String] = [
        "agy": "curl -fsSL https://antigravity.google/cli/install.sh | bash",
        "aider": "python -m pip install aider-install && aider-install",
        "opencode": "npm install -g opencode-ai",
        "goose": "brew install block-goose-cli",
    ]

    /// How to install the program a command starts, when we know it.
    static func installHint(for command: String) -> String? {
        installHints[firstWord(of: command)]
    }

    /// The program name when the command is a plain invocation; nil for anything
    /// with shell syntax (`a; b`, pipes, redirects, quotes), which we do not inspect.
    static func firstWord(of command: String) -> String {
        command.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
    }

    static func isPlainProgram(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isLetter || $0.isNumber || "._-/".contains($0) }
    }

    /// Entries earlier builds saved that are now built in (Antigravity) or discontinued
    /// (Gemini). Any legacy Gemini entry is removed: its saved tabs migrate to built-in
    /// Antigravity, which runs `agy`.
    static func migrated(_ tools: [CustomTool]) -> [CustomTool] {
        tools.filter { tool in
            let isOldGemini = tool.id == "gemini"
            let isOldAntigravity = tool.id == "antigravity"
            return !isOldGemini && !isOldAntigravity
        }
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
    /// Claude or Codex: the agents with usage limits, approval prompts and answer copying.
    case agent(AgentProvider)
    /// Google's Antigravity CLI (`agy`), with usage but no screen parsing.
    case antigravity
    case custom(String)

    /// Names of the built-in tiles, which a registered tool may not take (compared lower-cased).
    static let reservedNames = ["claude", "codex", "antigravity", "terminal"]

    /// The command that starts Antigravity.
    static let antigravityCommand = "agy"

    /// Stable text form, used as a dictionary key and when saving tabs.
    var id: String {
        switch self {
        case .shell: return "shell"
        case .agent(let provider): return provider.rawValue
        case .antigravity: return "antigravity"
        case .custom(let id): return "custom:\(id)"
        }
    }

    init?(id: String) {
        if id == "shell" { self = .shell }
        else if id == "antigravity" || id == "custom:antigravity" || id == "custom:gemini" { self = .antigravity }   // earlier builds kept it in the custom list
        else if let provider = AgentProvider(rawValue: id) { self = .agent(provider) }
        else if id.hasPrefix("custom:"), id.count > 7 { self = .custom(String(id.dropFirst(7))) }
        else { return nil }
    }

    /// Claude or Codex — the tools with usage limits, approval prompts and answer copying.
    var agent: AgentProvider? {
        if case .agent(let provider) = self { return provider }
        return nil
    }

    var usageProvider: AgentProvider? { self == .antigravity ? .antigravity : agent }

    var isShell: Bool { self == .shell }
    var isCustom: Bool { if case .custom = self { return true } else { return false } }
    /// A terminal program whose screen layout we do not read: no answer copying, no approval
    /// watching, and a pause before pasting into it.
    var isOtherCLI: Bool { isCustom || self == .antigravity }

    /// Name shown in tabs and titles.
    func displayName(customTools: [CustomTool] = AppSettings.shared.customTools) -> String {
        switch self {
        case .shell: return "Terminal"
        case .agent(let provider): return provider.displayName
        case .antigravity: return "Antigravity"
        case .custom(let id): return customTools.first { $0.id == id }?.name ?? tr("Ferramenta", "Tool")
        }
    }

    /// The tools shown in the picker and the drop strip, in order.
    static func all(customTools: [CustomTool] = AppSettings.shared.customTools) -> [Tool] {
        AgentProvider.allCases.map(\.tool) + customTools.map { .custom($0.id) } + [.shell]
    }
}
