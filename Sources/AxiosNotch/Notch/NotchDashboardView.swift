import SwiftUI

/// One provider's usage: the running 5-hour window and the last 7 days,
/// with a back button and a shortcut into the terminal.
struct NotchUsageView: View {
    @ObservedObject var controller: NotchWindowController
    let provider: AgentProvider
    let summary: AgentUsageSummary?
    let limits: LimitState
    /// Projections from `AgentUsageStore.forecasts`, keyed `provider.window`.
    let forecasts: [String: LimitForecast]

    private var accent: Color { NotchTheme.accent(for: provider) }

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(spacing: 10) {
                LimitCard(
                    title: tr("Janela de 5h", "5h window"), limit: limits.rateLimits?.fiveHour, state: limits, accent: accent,
                    resetText: { UsageFormat.remaining(until: $0, now: $1) },
                    footnote: footnote(summary?.fiveHourBlock),
                    forecast: forecasts["\(provider.rawValue).\(LimitWindow.fiveHour.rawValue)"]
                )
                LimitCard(
                    title: tr("Semana", "Week"), limit: limits.rateLimits?.weekly, state: limits, accent: accent,
                    resetText: { date, _ in UsageFormat.weekday(of: date) },
                    footnote: footnote(summary?.week),
                    forecast: forecasts["\(provider.rawValue).\(LimitWindow.weekly.rawValue)"]
                )
            }
            ModelUsageSection(
                provider: provider,
                models: summary?.weekModels ?? [],
                caps: limits.rateLimits?.modelLimits ?? []
            )
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
            IconButton(systemName: "terminal.fill", tint: accent, tool: .agent(provider), showsBadge: true) {
                controller.openTerminal(for: .agent(provider))
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

struct IconButton: View {
    let systemName: String
    var tint: Color = .white
    var tool: Tool = .shell
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
                    if showsBadge { SessionBadge(tool: tool).offset(x: 2, y: -3) }
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
    /// When present, replaces the tokens/cost footnote with the projection.
    var forecast: LimitForecast? = nil

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
                        Text((limit.resetsAt.map { resetText($0, context.date) } ?? " ") + staleSuffix(now: context.date))
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
                if let forecast, limit != nil {
                    Text(UsageFormat.forecastText(forecast.secondsToFull))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(red: 0.97, green: 0.68, blue: 0.25))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else if let footnote {
                    Text(footnote)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(height: 142)   // same height whether or not there is a footnote
        .animation(.smooth, value: limit)
    }

    /// Shown when the numbers come from earlier (the provider is rate-limiting
    /// us, or the app just started): "· há 12 min".
    private func staleSuffix(now: Date) -> String {
        guard let fetched = state.rateLimits?.fetchedAt else { return "" }
        return UsageFormat.ageSuffix(since: fetched, now: now)
    }

    private var message: String {
        switch state {
        case .loading: return tr("Carregando…", "Loading…")
        case .unavailable(let reason): return reason
        case .available: return tr("Sem dados desta janela", "No data for this window")
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

/// Which models the last 7 days went to: one proportional bar plus a legend,
/// and — when the plan reports weekly caps per model — how much of each cap
/// is used. Shares follow spend when pricing is known, else tokens.
private struct ModelUsageSection: View {
    let provider: AgentProvider
    let models: [AgentModelUsage]
    let caps: [AgentModelLimit]

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let share: Double
        let color: Color
    }

    private var palette: [Color] {
        switch provider {
        case .claude:
            return [NotchTheme.claudeAccent, Color(red: 0.96, green: 0.74, blue: 0.50), Color(red: 0.52, green: 0.72, blue: 0.95), .white.opacity(0.35)]
        case .codex:
            return [NotchTheme.codexAccent, Color(red: 0.70, green: 0.55, blue: 1.0), Color(red: 0.40, green: 0.85, blue: 0.80), .white.opacity(0.35)]
        }
    }

    private var slices: [Slice] {
        let totalCost = models.reduce(0) { $0 + $1.cost }
        let useCost = totalCost > 0
        let total = useCost ? totalCost : Double(models.reduce(0) { $0 + $1.tokens })
        guard total > 0 else { return [] }
        func value(_ m: AgentModelUsage) -> Double { useCost ? m.cost : Double(m.tokens) }

        let top = models.prefix(3)
        var result = top.enumerated().map { index, model in
            Slice(id: model.name, name: ModelName.display(model.name), share: value(model) / total, color: palette[index])
        }
        let rest = models.dropFirst(3).reduce(0) { $0 + value($1) }
        if rest > 0 { result.append(Slice(id: "others", name: tr("Outros", "Others"), share: rest / total, color: palette[3])) }
        return result
    }

    /// A sliver of a percent reads "<1%", not a misleading "0%".
    private func percentText(_ share: Double) -> String {
        let percent = Int((share * 100).rounded())
        return percent == 0 ? "<1%" : "\(percent)%"
    }

    private var capsText: String? {
        guard !caps.isEmpty else { return nil }
        return caps.map { "\($0.label) \(Int($0.limit.percent.rounded()))%" }.joined(separator: " · ")
    }

    var body: some View {
        Card(title: tr("Por modelo", "By model"), trailing: capsText.map { tr("Limite: \($0)", "Limit: \($0)") } ?? tr("7 dias", "7 days")) {
            if slices.isEmpty {
                Text(tr("Sem uso nos últimos 7 dias", "No usage in the last 7 days"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            ForEach(slices) { slice in
                                Capsule()
                                    .fill(slice.color)
                                    .frame(width: max(4, (proxy.size.width - CGFloat(slices.count - 1) * 2) * slice.share))
                            }
                        }
                    }
                    .frame(height: 6)
                    HStack(spacing: 12) {
                        ForEach(slices) { slice in
                            HStack(spacing: 5) {
                                Circle().fill(slice.color).frame(width: 6, height: 6)
                                Text("\(slice.name) \(percentText(slice.share))")
                                    .font(.system(size: 10.5))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(height: 76)
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

    /// " · há 12 min" once data is older than a few minutes; nothing while fresh.
    static func ageSuffix(since fetched: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(fetched) / 60)
        guard minutes >= 4 else { return "" }
        return minutes >= 60
            ? tr(" · há \(minutes / 60) h", " · \(minutes / 60) h ago")
            : tr(" · há \(minutes) min", " · \(minutes) min ago")
    }

    /// "no ritmo atual, acaba em ~40 min". Rounds to 5 minutes (a projection is
    /// never that exact) and to half hours beyond the first couple of hours.
    static func forecastText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let amount: String
        if minutes < 10 {
            amount = "\(minutes) min"
        } else if minutes < 60 {
            amount = "\(Int((Double(minutes) / 5).rounded()) * 5) min"
        } else if minutes < 6 * 60 {
            let rounded = Int((Double(minutes) / 5).rounded()) * 5
            amount = rounded % 60 == 0 ? "\(rounded / 60) h" : "\(rounded / 60) h \(rounded % 60) min"
        } else if minutes < 48 * 60 {
            amount = "\(Int((Double(minutes) / 60).rounded())) h"
        } else {
            amount = tr("\(Int((Double(minutes) / 1440).rounded())) dias", "\(Int((Double(minutes) / 1440).rounded())) days")
        }
        return tr("no ritmo atual, acaba em ~\(amount)", "at this pace, runs out in ~\(amount)")
    }

    static func weekday(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Localization.current == .pt ? "pt_BR" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate(Localization.current == .pt ? "EEE HH:mm" : "EEE h:mm a")
        let when = formatter.string(from: date)
        return tr("reinicia \(when)", "resets \(when)")
    }

    static func remaining(until end: Date, now: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(now) / 60))
        return minutes >= 60
            ? tr("reinicia em \(minutes / 60)h \(minutes % 60)min", "resets in \(minutes / 60)h \(minutes % 60)min")
            : tr("reinicia em \(minutes)min", "resets in \(minutes)min")
    }
}
