import SwiftUI

/// Shared look for the notch panels: soft glass tiles on pure black.
enum NotchTheme {
    static let claudeAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codexAccent = Color(red: 0.47, green: 0.55, blue: 1.0)

    static func accent(for provider: AgentProvider) -> Color {
        switch provider {
        case .claude: return claudeAccent
        case .codex: return codexAccent
        }
    }

    static let tileFill = LinearGradient(
        colors: [.white.opacity(0.10), .white.opacity(0.05)],
        startPoint: .top, endPoint: .bottom
    )
    static let tileHoverFill = LinearGradient(
        colors: [.white.opacity(0.17), .white.opacity(0.09)],
        startPoint: .top, endPoint: .bottom
    )
    static let hairline = Color.white.opacity(0.09)
}

/// Provider glyph at a given size, shared by the picker tiles and headers.
struct ProviderGlyph: View {
    let provider: AgentProvider
    var size: CGFloat = 32

    var body: some View {
        switch provider {
        case .claude: ClaudeMascot().frame(width: size * 1.1, height: size * 0.88)
        case .codex: CodexCloud().frame(width: size, height: size)
        }
    }
}
