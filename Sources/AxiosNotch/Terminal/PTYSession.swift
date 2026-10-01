import Foundation

/// Launch arguments for the embedded terminal, always through the user's
/// login shell so PATH and shell profile (nvm, asdf, custom aliases, etc.)
/// are respected. With a provider it runs that CLI the way a user would from
/// a normal terminal; with `nil` it is just a clean interactive shell and the
/// user chooses what to run.
enum PTYSession {
    static func launchArguments(for provider: AgentProvider?) -> (executable: String, args: [String]) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let provider else { return (shell, ["-l"]) }
        return (shell, ["-l", "-c", provider.launchCommand])
    }
}
