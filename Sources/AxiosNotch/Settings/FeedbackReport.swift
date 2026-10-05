import AppKit
import Foundation

/// The "Send feedback" mail: a pre-filled message to the developer with a short
/// diagnostic block. It never includes tokens, conversations, folder paths or the
/// commands of the user's own tools, only versions, preferences and states.
enum FeedbackReport {
    static let recipient = "axios.devteam@gmail.com"

    struct Snapshot {
        var version: String
        var build: String
        var macOS: String
        var model: String
        var language: String
        var preferences: [(String, String)]
        var tools: [(String, String)]
        var usage: [(String, String)]
        var openTabs: Int
        var customToolCount: Int
    }

    /// The text under the "---" line of the e-mail.
    static func diagnostics(_ s: Snapshot) -> String {
        var lines = [
            "Axios Notch \(s.version) (\(s.build))",
            "macOS \(s.macOS) · \(s.model)",
            "Idioma: \(s.language)",
            "",
            "Preferências:",
        ]
        lines += s.preferences.map { "  \($0.0): \($0.1)" }
        lines += ["", "Ferramentas:"]
        lines += s.tools.map { "  \($0.0): \($0.1)" }
        lines.append("  ferramentas próprias: \(s.customToolCount)")
        lines += ["", "Uso do plano:"]
        lines += s.usage.map { "  \($0.0): \($0.1)" }
        lines += ["", "Abas abertas: \(s.openTabs)"]
        return lines.joined(separator: "\n")
    }

    static func body(_ s: Snapshot, intro: String) -> String {
        "\(intro)\n\n\n---\n\(diagnostics(s))\n"
    }

    static func mailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.percentEncodedQuery = "subject=\(encode(subject))&body=\(encode(body))"
        return components.url
    }

    /// `URLComponents` leaves `&`, `+` and `=` alone in a query, which would split
    /// or corrupt the message, so everything but unreserved characters is encoded.
    static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// Whether a program is installed in one of the usual places (the app does not
    /// run through the user's shell, so `PATH` is not reliable).
    static func isInstalled(_ program: String, home: String = NSHomeDirectory(), fileManager: FileManager = .default) -> Bool {
        let folders = ["\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.npm-global/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return folders.contains { fileManager.isExecutableFile(atPath: "\($0)/\(program)") }
    }

    @MainActor
    static func snapshot(settings: AppSettings, usage: AgentUsageStore, sessions: TerminalSessionStore) -> Snapshot {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        func state(_ provider: AgentProvider) -> String {
            switch usage.limits[provider] {
            case .available: return "ok"
            case .loading, nil: return "carregando"
            case .unavailable(let reason): return "indisponível (\(reason))"
            }
        }
        return Snapshot(
            version: info?["CFBundleShortVersionString"] as? String ?? "dev",
            build: info?["CFBundleVersion"] as? String ?? "0",
            macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            model: hardwareModel(),
            language: Localization.current == .en ? "English" : "Português",
            preferences: [
                ("tema", settings.terminalTheme.rawValue),
                ("fonte", "\(settings.terminalFont.label) \(Int(settings.terminalFontSize))"),
                ("destaque", settings.accent.rawValue),
                ("reabrir abas", settings.reopenTabs ? "sim" : "não"),
                ("aviso de resposta", settings.finishBanner ? "sim (\(settings.bannerSeconds) s)" : "não"),
                ("som", settings.soundOnNotice ? settings.soundChoice.rawValue : "não"),
                ("vibração", settings.hoverHaptic ? String(describing: settings.hapticStrength) : "não"),
            ],
            tools: ["claude", "codex", "agy"].map { ($0, isInstalled($0) ? "instalado" : "não encontrado") },
            usage: AgentProvider.allCases.map { ($0.displayName, state($0)) },
            openTabs: sessions.keys.count,
            customToolCount: settings.customTools.count
        )
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
