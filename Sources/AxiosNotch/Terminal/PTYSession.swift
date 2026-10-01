import Foundation

/// Launch arguments for running a provider's CLI the same way a user would
/// from a normal terminal: through their login shell, so PATH and shell
/// profile (nvm, asdf, custom aliases, etc.) are respected.
enum PTYSession {
    static func launchArguments(for provider: AgentProvider) -> (executable: String, args: [String]) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return (shell, ["-l", "-c", provider.launchCommand])
    }
}
