import Foundation

/// Something the closed notch announces by growing a banner: an answer that
/// finished while the user was away, or a plan limit getting close.
struct NotchNotice: Equatable {
    enum Level: Equatable { case info, warning, critical }
    /// What clicking the banner does.
    enum Action: Equatable { case openTerminal, openUsage }

    /// The tool that answered (or is waiting).
    let tool: Tool
    /// Folder the session was working in, when it says anything useful.
    let project: String?
    /// What the notch says about it ("Te respondi aqui!").
    let phrase: String
    var level: Level = .info
    var action: Action = .openTerminal
    /// The exact terminal tab that answered, so the click can open that one.
    var sessionID: String? = nil
    let id = UUID()
}
