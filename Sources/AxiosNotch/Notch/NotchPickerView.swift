import SwiftUI

/// "Active tools": one large tile each for Claude, Codex and the terminal.
struct NotchPickerView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject private var sessions = TerminalSessionStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Ferramentas ativas", "Active tools"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 4)

            HStack(spacing: 10) {
                ForEach(Tool.all(customTools: settings.customTools), id: \.id) { tool in
                    ToolTile(title: tool.displayName(customTools: settings.customTools), tint: NotchTheme.accent(for: tool), tool: tool) {
                        ToolGlyph(tool: tool, size: 30)
                    } action: {
                        // Claude and Codex open their usage first (with a terminal button);
                        // everything else goes straight to its terminal.
                        if let provider = tool.agent { controller.showUsage(for: provider) } else { controller.openTerminal(for: tool) }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
        .padding(.top, 4)
        // Small and out of the way: the tools are the point. It floats in the
        // top-right corner, above the Terminal tile, without taking a row.
        .overlay(alignment: .topTrailing) {
            GearButton { controller.showSettings() }
                .padding(.trailing, 8)
                .padding(.top, 3)
        }
    }
}

/// Small round settings button.
private struct GearButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(hovering ? 0.2 : 0.09)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Ajustes", "Settings"))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct ToolTile<Glyph: View>: View {
    let title: String
    let tint: Color
    /// Which terminal session this tile fronts (`nil` is the clean shell).
    let tool: Tool
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
                SessionBadge(tool: tool).padding(8)
            }
            .scaleEffect(hovering && !AppSettings.shared.reduceMotion ? 1.04 : 1)
            .shadow(color: tint.opacity(hovering ? 0.25 : 0), radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { hovering = $0 }
        .animation(NotchMotion.spring(response: 0.3, damping: 0.7), value: hovering)
    }
}

private let activeGreen = Color(red: 0.30, green: 0.85, blue: 0.45)
private let unreadRed = Color(red: 0.95, green: 0.27, blue: 0.27)

/// Small green dot with a slow pulse: "a session is running here".
struct ActiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(activeGreen)
            .frame(width: 7, height: 7)
            .background(
                Circle()
                    .fill(activeGreen.opacity(0.5))
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.8)
            )
            .onAppear {
                guard !AppSettings.shared.reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

/// Three dots hopping in sequence: "an answer is loading".
struct BouncingDots: View {
    var color: Color = activeGreen
    var dot: CGFloat = 4

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let reduced = AppSettings.shared.reduceMotion
            HStack(spacing: dot * 0.6) {
                ForEach(0..<3, id: \.self) { index in
                    // A short hop, then rest, staggered across the three dots.
                    // With reduce-motion on they fade in turn instead of hopping.
                    let hop = max(0, sin(t * 7 - Double(index) * 0.8))
                    Circle()
                        .fill(color)
                        .frame(width: dot, height: dot)
                        .opacity(reduced ? 0.35 + 0.65 * hop : 1)
                        .offset(y: reduced ? 0 : -dot * 0.9 * hop)
                }
            }
        }
        .padding(.top, dot) // room for the hop so it isn't clipped
    }
}

/// "!" in an amber disc: the tool stopped and needs the user.
struct WaitingBadge: View {
    var size: CGFloat = 15
    @State private var pulse = false

    var body: some View {
        Text("!")
            .font(.system(size: size * 0.7, weight: .heavy, design: .rounded))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(red: 0.97, green: 0.68, blue: 0.25)))
            .scaleEffect(pulse ? 1.12 : 1)
            .onAppear {
                guard !AppSettings.shared.reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityLabel(tr("Aguardando aprovação", "Waiting for approval"))
    }
}

/// Red count of answers that finished while the user was away.
struct UnreadBadge: View {
    let count: Int
    var size: CGFloat = 15

    var body: some View {
        Text("\(min(count, 99))")
            .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, count > 9 ? 3 : 0)
            .background(Capsule().fill(unreadRed))
            .transition(.scale.combined(with: .opacity))
    }
}

/// What a terminal session is doing, in order of priority: answering
/// (bouncing dots) → unseen answers (red count) → merely alive (green dot).
struct SessionBadge: View {
    @ObservedObject private var sessions = TerminalSessionStore.shared
    let tool: Tool

    var body: some View {
        Group {
            if sessions.isWaiting(tool) {
                WaitingBadge()
            } else if sessions.isWorking(tool) {
                BouncingDots()
            } else if sessions.unreadCount(tool) > 0 {
                UnreadBadge(count: sessions.unreadCount(tool))
            } else if sessions.isActive(tool) {
                ActiveDot()
            }
        }
        .animation(NotchMotion.spring(response: 0.3, damping: 0.7), value: sessions.unreadCount(tool))
    }
}
