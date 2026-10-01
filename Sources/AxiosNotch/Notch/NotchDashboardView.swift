import SwiftUI

/// The rich per-provider view shown while the notch is expanded: today's
/// spend and hourly trend, a breakdown by model and by project, and a
/// GitHub-style activity heatmap over the last 13 weeks.
struct NotchDashboardView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject var usageStore: AgentUsageStore

    private var summary: AgentUsageSummary? {
        usageStore.summaries[controller.selectedProvider]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let summary, summary.hasAnySession {
                        SpendTrendCard(summary: summary)
                        HStack(alignment: .top, spacing: 12) {
                            NamedSpendCard(title: "Modelos", entries: summary.modelSpendToday)
                            NamedSpendCard(title: "Projetos", entries: summary.projectSpendToday)
                        }
                        ActivityHeatmapCard(summary: summary)
                    } else {
                        emptyState
                    }
                }
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
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.white.opacity(0.12), in: Circle())
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
        .padding(.top, 20)
    }
}

private struct ProviderTabBar: View {
    let selected: AgentProvider
    let onSelect: (AgentProvider) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AgentProvider.allCases) { provider in
                Button { onSelect(provider) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: provider.symbolName)
                        Text(provider.displayName)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        provider == selected ? Color.white.opacity(0.16) : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(provider == selected ? .white : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            content
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SpendTrendCard: View {
    let summary: AgentUsageSummary

    private var maxHourlySpend: Double {
        summary.hourlySpendToday.max() ?? 0
    }

    var body: some View {
        DashboardCard(title: "Gastos hoje", trailing: costLabel(summary.estimatedCostToday)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(costLabel(summary.estimatedCostToday) ?? "sem custo estimado")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(formattedTokens(summary.todayTokens.totalTokens)) tokens hoje")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        let value = summary.hourlySpendToday[hour]
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.orange.opacity(value > 0 ? 0.85 : 0.12))
                            .frame(height: barHeight(for: value))
                    }
                }
                .frame(height: 36, alignment: .bottom)
            }
        }
    }

    private func barHeight(for value: Double) -> CGFloat {
        guard maxHourlySpend > 0 else { return 2 }
        return max(2, CGFloat(value / maxHourlySpend) * 36)
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

private struct NamedSpendCard: View {
    let title: String
    let entries: [AgentNamedSpend]

    var body: some View {
        DashboardCard(title: title) {
            if entries.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries.prefix(3)) { entry in
                        HStack {
                            Text(entry.name)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                            Spacer()
                            Text("$\(String(format: "%.2f", entry.cost))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityHeatmapCard: View {
    let summary: AgentUsageSummary

    var body: some View {
        DashboardCard(title: "Atividade", trailing: "\(summary.activeDaysInHistory) dias ativos") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: 3) {
                            ForEach(Array(column.enumerated()), id: \.offset) { _, cost in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.orange.opacity(intensity(for: cost)))
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }

                HStack {
                    Text("$\(String(format: "%.2f", summary.totalCostInHistory)) em 13 semanas")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if let busiest = summary.busiestDay {
                        Text("Pico: $\(String(format: "%.2f", busiest.cost))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private var columns: [[Double]] {
        ActivityHeatmapLayout.columns(history: summary.dailyHistory, now: Date(), calendar: .current)
    }

    private var maxCost: Double {
        summary.busiestDay?.cost ?? 0
    }

    private func intensity(for cost: Double) -> Double {
        guard cost > 0 else { return 0.08 }
        guard maxCost > 0 else { return 0.08 }
        return 0.25 + 0.75 * min(1, cost / maxCost)
    }
}
