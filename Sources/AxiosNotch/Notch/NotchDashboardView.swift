import SwiftUI

/// The compact per-provider summary shown while the notch is expanded —
/// icon, today's spend, and a tiny hourly sparkline, sized like a landscape
/// widget card rather than a tall scrolling dashboard.
struct NotchDashboardView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject var usageStore: AgentUsageStore

    private var summary: AgentUsageSummary? {
        usageStore.summaries[controller.selectedProvider]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let summary, summary.hasAnySession {
                CompactUsageRow(provider: controller.selectedProvider, summary: summary)
            } else {
                emptyState
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            ProviderTabBar(selected: controller.selectedProvider) { controller.selectProvider($0) }
            Spacer()
            Button {
                controller.openTerminal(for: controller.selectedProvider)
            } label: {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sem sessão local de \(controller.selectedProvider.displayName)")
                .foregroundStyle(.white.opacity(0.8))
                .font(.subheadline)
            Text("Abra o terminal e rode \(controller.selectedProvider.launchCommand) pra começar.")
                .foregroundStyle(.white.opacity(0.5))
                .font(.caption)
        }
        .padding(.top, 8)
    }
}

private struct ProviderTabBar: View {
    let selected: AgentProvider
    let onSelect: (AgentProvider) -> Void
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AgentProvider.allCases) { provider in
                let isSelected = provider == selected
                Button { onSelect(provider) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: provider.symbolName)
                        Text(provider.displayName)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                                .matchedGeometryEffect(id: "providerTab", in: animation)
                        }
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .animation(.smooth(duration: 0.25), value: selected)
            }
        }
    }
}

/// Album-art-style icon on the left, name/cost/sparkline on the right —
/// the same shape as a landscape media-player widget.
private struct CompactUsageRow: View {
    let provider: AgentProvider
    let summary: AgentUsageSummary

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: provider.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(costLabel(summary.estimatedCostToday) ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Text("\(formattedTokens(summary.todayTokens.totalTokens)) tokens hoje")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
                sparkline
            }
        }
    }

    private var sparkline: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<24, id: \.self) { hour in
                let value = summary.hourlySpendToday[hour]
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange.opacity(value > 0 ? 0.85 : 0.15))
                    .frame(height: barHeight(for: value))
            }
        }
        .frame(height: 18, alignment: .bottom)
    }

    private func barHeight(for value: Double) -> CGFloat {
        let maxValue = summary.hourlySpendToday.max() ?? 0
        guard maxValue > 0 else { return 1.5 }
        return max(1.5, CGFloat(value / maxValue) * 18)
    }

    private func costLabel(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "$\(String(format: "%.2f", value))"
    }

    private func formattedTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }
}
