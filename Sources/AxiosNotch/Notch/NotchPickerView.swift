import AppKit
import SwiftUI

/// "Active tools": one large tile each for Claude, Codex and the terminal.
struct NotchPickerView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject var usageStore: AgentUsageStore
    @ObservedObject private var sessions = TerminalSessionStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateStore.shared
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Ferramentas ativas", "Active tools"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    Text(statusSummary)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
                Menu {
                    if sessions.recents.paths.isEmpty {
                        Text(tr("Nenhuma sessão recente", "No recent sessions"))
                    } else {
                        ForEach(sessions.recents.suggestions(), id: \.self) { path in
                            Menu(path.split(separator: "/").last.map(String.init) ?? path) {
                                ForEach(Tool.all(customTools: settings.customTools), id: \.id) { tool in
                                    Button(tool.displayName(customTools: settings.customTools)) {
                                        _ = sessions.openSession(tool, directory: path)
                                        controller.openTerminal(for: tool)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 23, height: 23)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(tr("Sessões recentes", "Recent sessions"))
                GearButton(badge: updates.availableRelease != nil) { controller.showSettings() }
            }
            .padding(.horizontal, 3)

            HStack(spacing: 10) {
                ForEach(Tool.all(customTools: settings.customTools), id: \.id) { tool in
                    ToolTile(title: tool.displayName(customTools: settings.customTools), tint: NotchTheme.accent(for: tool), tool: tool, limit: limit(for: tool)) {
                        ToolGlyph(tool: tool, size: 30)
                    } action: {
                        // Claude and Codex open their usage first (with a terminal button);
                        // everything else goes straight to its terminal.
                        if let provider = tool.agent { controller.showUsage(for: provider) } else { controller.openTerminal(for: tool) }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 13)
        .padding(.top, 5)
        .overlay {
            if !hasSeenOnboarding { WelcomeCard { hasSeenOnboarding = true } }
        }
    }

    private var statusSummary: String {
        let working = Tool.all(customTools: settings.customTools).filter { sessions.isWorking($0) }.count
        let waiting = Tool.all(customTools: settings.customTools).filter { sessions.isWaiting($0) }.count
        if waiting > 0 { return tr("\(waiting) aguardando você", "\(waiting) waiting for you") }
        if working > 0 { return tr("\(working) trabalhando", "\(working) working") }
        return tr("Tudo pronto", "All caught up")
    }

    private func limit(for tool: Tool) -> AgentLimit? {
        guard let provider = tool.agent, case .available(let limits) = usageStore.limits[provider] else { return nil }
        return limits.fiveHour
    }
}

private struct WelcomeCard: View {
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(.white)
            Text("Axios Notch").font(.system(size: 13, weight: .bold))
            Text(tr("Acompanhe seus agentes, abra sessões e arraste arquivos para o notch.", "Track agents, open sessions, and drag files to the notch."))
                .multilineTextAlignment(.center).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            Button(tr("Começar", "Get started"), action: dismiss).buttonStyle(.borderedProminent)
        }
        .padding(18).frame(width: 230)
        .background(RoundedRectangle(cornerRadius: 18).fill(NotchTheme.panelFill).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.16))))
    }
}

/// Small round settings button.
private struct GearButton: View {
    var badge = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 23, height: 23)
                .background(Circle().fill(.white.opacity(hovering ? 0.20 : 0.08)))
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(Color(red: 0.33, green: 0.58, blue: 0.96)).frame(width: 7, height: 7) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge ? tr("Ajustes, atualização disponível", "Settings, update available") : tr("Ajustes", "Settings"))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct ToolTile<Glyph: View>: View {
    let title: String
    let tint: Color
    /// Which terminal session this tile fronts (`nil` is the clean shell).
    let tool: Tool
    let limit: AgentLimit?
    @ViewBuilder let glyph: () -> Glyph
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                glyph()
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint.opacity(0.13)))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 1 : 0.8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hovering ? NotchTheme.tileHoverFill : NotchTheme.tileFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(hovering ? tint.opacity(0.45) : NotchTheme.hairline, lineWidth: 1)
                    }
            }
            // Plan usage at the top left, session state (active dot, unread count) at the top right.
            .overlay(alignment: .topLeading) {
                if let limit { LimitRing(percent: limit.percent, tint: tint).padding(8) }
            }
            .overlay(alignment: .topTrailing) {
                SessionBadge(tool: tool).padding(8)
            }
            .scaleEffect(hovering && !AppSettings.shared.reduceMotion ? 1.04 : 1)
            .shadow(color: tint.opacity(hovering ? 0.25 : 0), radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .contextMenu {
            Button(tr("Nova sessão", "New session")) { TerminalSessionStore.shared.openSession(tool, directory: nil) }
            if let key = TerminalSessionStore.shared.selectedKey(for: tool), TerminalSessionStore.shared.hasAnswer(for: key) {
                Button(tr("Copiar última resposta", "Copy last answer")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(TerminalSessionStore.shared.lastAnswer(for: key) ?? "", forType: .string) }
            }
            if let key = TerminalSessionStore.shared.selectedKey(for: tool) { Button(tr("Encerrar sessão", "Close session"), role: .destructive) { TerminalSessionStore.shared.close(key) } }
        }
        .onHover { hovering = $0 }
        .animation(NotchMotion.spring(response: 0.3, damping: 0.7), value: hovering)
    }
}

private struct LimitRing: View {
    let percent: Double; let tint: Color
    var body: some View { Circle().stroke(.white.opacity(0.16), lineWidth: 2).overlay(Circle().trim(from: 0, to: min(percent / 100, 1)).stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))).frame(width: 13, height: 13).accessibilityLabel("\(Int(percent))%") }
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
