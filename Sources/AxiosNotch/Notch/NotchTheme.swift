import SwiftUI

/// Shared look for the notch panels: soft glass tiles on pure black.
enum NotchTheme {
    static let claudeAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codexAccent = Color(red: 0.45, green: 0.80, blue: 0.70)

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

/// The little pixel mascot used for Claude, drawn on a 9×6 grid.
struct PixelMascot: View {
    var color: Color = NotchTheme.claudeAccent

    var body: some View {
        Canvas { context, size in
            let cols = 9.0, rows = 6.0
            let unit = min(size.width / cols, size.height / rows)
            let ox = (size.width - unit * cols) / 2
            let oy = (size.height - unit * rows) / 2
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
                Path(CGRect(x: ox + x * unit, y: oy + y * unit, width: w * unit, height: h * unit))
            }
            context.fill(rect(1, 0, 7, 4), with: .color(color))   // body
            context.fill(rect(0, 1, 9, 2), with: .color(color))   // arms
            for x in [1.0, 2.0, 6.0, 7.0] { context.fill(rect(x, 4, 1, 2), with: .color(color)) } // legs
            context.fill(rect(2, 1, 1, 1.5), with: .color(.black.opacity(0.85)))  // eyes
            context.fill(rect(6, 1, 1, 1.5), with: .color(.black.opacity(0.85)))
        }
    }
}

/// Provider glyph at a given size, shared by the picker tiles and headers.
struct ProviderGlyph: View {
    let provider: AgentProvider
    var size: CGFloat = 32

    var body: some View {
        switch provider {
        case .claude:
            PixelMascot().frame(width: size * 1.1, height: size * 0.75)
        case .codex:
            Image(systemName: provider.symbolName)
                .font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(NotchTheme.codexAccent)
                .frame(width: size, height: size)
        }
    }
}
