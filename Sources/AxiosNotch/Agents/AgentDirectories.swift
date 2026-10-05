import Foundation

/// Logs and credentials must use the same CLI configuration directory.
enum AgentDirectories {
    static func configuration(for provider: AgentProvider,
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if provider == .antigravity {
            return home.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
        }
        let key = provider == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
        if let path = environment[key], !path.isEmpty { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(provider == .claude ? ".claude" : ".codex", isDirectory: true)
    }
}
