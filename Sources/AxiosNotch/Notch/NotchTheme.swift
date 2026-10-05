import SwiftUI

/// Shared look for the notch panels: soft glass tiles on pure black.
enum NotchTheme {
    static let claudeAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codexAccent = Color(red: 0.47, green: 0.55, blue: 1.0)

    /// The app's own accent, chosen in the settings.
    static var appAccent: Color { AppSettings.shared.accent.color }

    static func accent(for provider: AgentProvider) -> Color {
        switch provider {
        case .claude: return claudeAccent
        case .codex: return codexAccent
        case .antigravity: return Color(red: 0.42, green: 0.55, blue: 0.98)
        }
    }

    /// A tool's colour: its brand colour for Claude and Codex, the app accent for
    /// the terminal, and a stable colour from the name for the user's own tools.
    static func accent(for tool: Tool) -> Color {
        switch tool {
        case .shell: return appAccent
        case .agent(let provider): return accent(for: provider)
        case .antigravity: return Color(red: 0.42, green: 0.55, blue: 0.98)
        case .custom: return customAccent(named: tool.displayName())
        }
    }

    /// Same name, same colour, every launch (Swift's own hashing is randomised).
    static func customAccent(named name: String) -> Color {
        let hue = Double(customHue(for: name)) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.95)
    }

    static func customHue(for name: String) -> Int {
        var hash: UInt32 = 5381
        for byte in name.lowercased().utf8 { hash = hash &* 33 &+ UInt32(byte) }
        return Int(hash % 360)
    }

    /// A charcoal surface rather than flat black: it retains the notch's dark
    /// character while giving panels the depth of a native macOS popover.
    static let panelFill = LinearGradient(
        colors: [Color(red: 0.075, green: 0.078, blue: 0.087), Color(red: 0.018, green: 0.019, blue: 0.024)],
        startPoint: .top, endPoint: .bottom
    )

    static let tileFill = LinearGradient(
        colors: [.white.opacity(0.115), .white.opacity(0.045)],
        startPoint: .top, endPoint: .bottom
    )
    static let tileHoverFill = LinearGradient(
        colors: [.white.opacity(0.20), .white.opacity(0.085)],
        startPoint: .top, endPoint: .bottom
    )
    static let hairline = Color.white.opacity(0.12)
}

/// Provider glyph at a given size, shared by the picker tiles and headers.
struct ProviderGlyph: View {
    let provider: AgentProvider
    var size: CGFloat = 32

    var body: some View {
        switch provider {
        case .claude: ClaudeMascot().frame(width: size * 1.1, height: size * 0.88)
        case .codex: CodexCloud().frame(width: size, height: size)
        case .antigravity: AntigravityMark().frame(width: size, height: size)
        }
    }
}


/// The icon for any tool: the real artwork for Claude, Codex and the terminal,
/// and a coloured tile with the first letter for the user's own tools.
struct ToolGlyph: View {
    let tool: Tool
    var size: CGFloat = 32

    var body: some View {
        switch tool {
        case .agent(let provider): ProviderGlyph(provider: provider, size: size)
        case .shell: TerminalIcon().frame(width: size, height: size)
        case .antigravity:
            AntigravityMark().frame(width: size, height: size)
        case .custom:
            let name = tool.displayName()
            let color = NotchTheme.accent(for: tool)
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay {
                    Text(CustomTool.initial(for: name))
                        .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.78))
                }
        }
    }
}
