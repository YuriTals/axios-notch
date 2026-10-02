import Foundation

/// Launch arguments for the embedded terminal, always through the user's
/// login shell so PATH and shell profile (nvm, asdf, custom aliases, etc.)
/// are respected. With a provider it runs that CLI the way a user would from
/// a normal terminal; with `nil` it is just a clean interactive shell and the
/// user chooses what to run.
enum PTYSession {
    /// The user's login shell, falling back to zsh (the macOS default).
    static func loginShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = environment["SHELL"], !shell.isEmpty { return shell }
        return "/bin/zsh"
    }

    /// Runs the tool, or — when the program is not installed — says so, shows how to
    /// install it and leaves a shell open. Without this a missing program would print
    /// "command not found" and the tab would vanish before it could be read.
    ///
    /// The shell to hand over to is written into the script: an app opened from the
    /// Finder has no `SHELL` in its environment, and `exec "$SHELL"` would then fail
    /// and take the tab down with it.
    static func customScript(for tool: CustomTool, shell: String = loginShell()) -> String {
        let word = CustomTool.firstWord(of: tool.command)
        guard CustomTool.isPlainProgram(word) else { return tool.command }
        let hint = CustomTool.installHint(for: tool.command)
        let title = tr("\(tool.name) não está instalado.", "\(tool.name) isn't installed.")
        let how = hint.map { tr("Instale com:", "Install with:") + "\n  \($0)\n" } ?? ""
        let message = "\n\(title)\n\(how)\n" + tr("Depois, abra de novo. Este terminal segue disponível.", "Then open it again. This terminal stays available.") + "\n\n"
        return "if command -v \(word) >/dev/null 2>&1; then \(tool.command); else printf '%s' '\(message.replacingOccurrences(of: "'", with: "'\\''"))'; exec '\(shell)' -l; fi"
    }

    static func launchArguments(for tool: Tool, customTools: [CustomTool] = AppSettings.shared.customTools) -> (executable: String, args: [String]) {
        let shell = loginShell()
        switch tool {
        case .shell: return (shell, ["-l"])
        case .agent(let provider): return (shell, ["-l", "-c", provider.launchCommand])
        case .antigravity:
            return (shell, ["-l", "-c", customScript(for: CustomTool(id: "antigravity", name: "Antigravity", command: Tool.antigravityCommand))])
        case .custom(let id):
            // The user's own command, run the way they would type it. A tool that
            // was removed meanwhile falls back to a plain shell.
            guard let tool = customTools.first(where: { $0.id == id }), !tool.command.isEmpty else { return (shell, ["-l"]) }
            return (shell, ["-l", "-c", customScript(for: tool)])
        }
    }
}
