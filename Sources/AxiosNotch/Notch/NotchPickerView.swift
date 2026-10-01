import SwiftUI

/// "Active tools": one large tile each for Claude, Codex and the terminal.
struct NotchPickerView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject private var sessions = TerminalSessionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ferramentas ativas")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 4)

            HStack(spacing: 10) {
                ForEach(AgentProvider.allCases) { provider in
                    ToolTile(title: provider.displayName, tint: NotchTheme.accent(for: provider), isActive: sessions.isActive(provider)) {
                        ProviderGlyph(provider: provider, size: 30)
                    } action: {
                        controller.showUsage(for: provider)
                    }
                }
                ToolTile(title: "Terminal", tint: .white, isActive: sessions.isActive(nil)) {
                    Image(systemName: "terminal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1.4))
                } action: {
                    controller.openTerminal(for: nil)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }
}

private struct ToolTile<Glyph: View>: View {
    let title: String
    let tint: Color
    /// A terminal session is running behind this tile.
    var isActive = false
    @ViewBuilder let glyph: () -> Glyph
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                glyph().frame(height: 32)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(hovering ? 1 : 0.8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(hovering ? NotchTheme.tileHoverFill : NotchTheme.tileFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(hovering ? tint.opacity(0.45) : NotchTheme.hairline, lineWidth: 1)
                    }
            }
            .overlay(alignment: .topTrailing) {
                if isActive { ActiveDot().padding(9) }
            }
            .scaleEffect(hovering ? 1.04 : 1)
            .shadow(color: tint.opacity(hovering ? 0.25 : 0), radius: 10)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
    }
}

/// Small green dot with a slow pulse: "a session is running here".
struct ActiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.30, green: 0.85, blue: 0.45))
            .frame(width: 7, height: 7)
            .background(
                Circle()
                    .fill(Color(red: 0.30, green: 0.85, blue: 0.45).opacity(0.5))
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.8)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
            .help("Sessão ativa")
    }
}
