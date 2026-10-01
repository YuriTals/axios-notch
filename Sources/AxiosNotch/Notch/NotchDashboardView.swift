import SwiftUI

/// One provider's usage: the running 5-hour window and the last 7 days,
/// with a back button and a shortcut into the terminal.
struct NotchUsageView: View {
    @ObservedObject var controller: NotchWindowController
    let provider: AgentProvider
    let summary: AgentUsageSummary?
    let limits: LimitState

    private var accent: Color { NotchTheme.accent(for: provider) }

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(spacing: 10) {
                LimitCard(
                    title: "Janela de 5h", limit: limits.rateLimits?.fiveHour, state: limits, accent: accent,
                    resetText: { UsageFormat.remaining(until: $0, now: $1) },
                    footnote: footnote(summary?.fiveHourBlock)
                )
                LimitCard(
                    title: "Semana", limit: limits.rateLimits?.weekly, state: limits, accent: accent,
                    resetText: { date, _ in UsageFormat.weekday(of: date) },
                    footnote: footnote(summary?.week)
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(systemName: "chevron.left") { controller.showPicker() }
            ProviderGlyph(provider: provider, size: 18)
            Text(provider.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            IconButton(systemName: "terminal.fill", tint: accent, provider: provider, showsBadge: true) {
                controller.openTerminal(for: provider)
            }
        }
    }

    private func footnote(_ window: AgentUsageWindow?) -> String? {
        guard let window, window.tokens.totalTokens > 0 else { return nil }
        return "\(UsageFormat.tokens(window.tokens.totalTokens)) tokens · \(UsageFormat.cost(window.cost))"
    }
}

extension LimitState {
    var rateLimits: AgentRateLimits? {
        if case .available(let limits) = self { return limits }
        return nil
    }
}

private struct IconButton: View {
    let systemName: String
    var tint: Color = .white
    var provider: AgentProvider?
    var showsBadge = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 26)
                .background(Capsule().fill(.white.opacity(hovering ? 0.18 : 0.09)))
                .overlay(alignment: .topTrailing) {
                    if showsBadge { SessionBadge(provider: provider).offset(x: 2, y: -3) }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct Card<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NotchTheme.tileFill)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotchTheme.hairline, lineWidth: 1))
        }
    }
}

/// One plan window: the provider's own % used, a bar, and when it resets.
/// Token and cost totals from the local logs are only a small footnote.
private struct LimitCard: View {
    let title: String
    let limit: AgentLimit?
    let state: LimitState
    let accent: Color
    let resetText: (Date, Date) -> String
    let footnote: String?

    private func tint(_ percent: Double) -> Color {
        if percent >= 90 { return Color(red: 0.95, green: 0.33, blue: 0.30) }
        if percent >= 70 { return Color(red: 0.97, green: 0.68, blue: 0.25) }
        return accent
    }

    var body: some View {
        Card(title: title, trailing: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if let limit {
                    let color = tint(limit.percent)
                    Text("\(Int(limit.percent.rounded()))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    ProgressBar(progress: min(max(limit.percent / 100, 0), 1), accent: color)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(limit.resetsAt.map { resetText($0, context.date) } ?? " ")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer(minLength: 0)
                    ProgressBar(progress: 0, accent: accent)
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .animation(.smooth, value: limit)
    }

    private var message: String {
        switch state {
        case .loading: return "Carregando…"
        case .unavailable(let reason): return reason
        case .available: return "Sem dados desta janela"
        }
    }
}

private struct ProgressBar: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.7), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(progress > 0 ? 6 : 0, proxy.size.width * progress))
            }
        }
        .frame(height: 6)
    }
}

private struct DayBars: View {
    let values: [Double]
    let accent: Color
    private let height: CGFloat = 22

    var body: some View {
        let maxValue = values.max() ?? 0
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { index in
                let isToday = index == values.count - 1
                let fraction = maxValue > 0 ? values[index] / maxValue : 0
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(values[index] > 0 ? accent.opacity(isToday ? 1 : 0.55) : .white.opacity(0.1))
                    .frame(height: max(4, height * fraction))
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

enum UsageFormat {
    static func tokens(_ value: Int) -> String {
        if value >= 100_000_000 { return String(format: "%.0fM", Double(value) / 1_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    static func cost(_ value: Double) -> String { String(format: "$%.2f", value) }

    static func weekday(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return "reinicia \(formatter.string(from: date))"
    }

    static func remaining(until end: Date, now: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(now) / 60))
        return minutes >= 60 ? "reinicia em \(minutes / 60)h \(minutes % 60)min" : "reinicia em \(minutes)min"
    }
}
