import AppKit
import SwiftUI

/// The settings pages. Each is a screenful of cards; the panel scrolls between
/// them with snap (trackpad / wheel) and a rail of icons on the right to jump,
/// like the iOS 26 Control Center.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .general: return "Ajustes"
        }
    }
}

/// Preferences, shown inside the notch like every other panel.
struct NotchSettingsView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject private var settings = AppSettings.shared
    /// The scroll position is tracked by the pages' own ids (the strings the
    /// `ForEach` gives them); an explicit `.id` of another type would never match.
    @State private var pageID: SettingsPage.ID? = SettingsPage.general.id
    private var page: SettingsPage { SettingsPage.allCases.first { $0.id == pageID } ?? .general }

    private let railWidth: CGFloat = 26

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                IconButton(systemName: "chevron.left") { controller.showPicker() }
                    .accessibilityLabel("Voltar")
                Text(page.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: pageID)
                Spacer()
                AppBadge()
            }

            HStack(alignment: .center, spacing: 10) {
                // On the left, mirroring the app badge in the header's right corner.
                PageRail(pageID: $pageID)
                    .frame(width: railWidth)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(SettingsPage.allCases) { item in
                            pageContent(item)
                                .frame(height: SettingsLayout.pageHeight)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $pageID)
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .frame(height: SettingsLayout.pageHeight)
                .clipped()
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.9))
        .toggleStyle(.switch)
        .tint(NotchTheme.claudeAccent)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func pageContent(_ page: SettingsPage) -> some View {
        switch page {
        case .general: generalPage
        }
    }

    // Blocks flow two per row; a lone block is centred.
    private var generalPage: some View {
        CardGridLayout {
            SettingsCard(title: "Geral") {
                Toggle("Iniciar ao fazer login", isOn: $settings.launchAtLogin)
                if let error = settings.loginError {
                    Caption(error, color: Color(red: 0.95, green: 0.45, blue: 0.4))
                } else if !LoginItem.isBundled {
                    Caption("Fora de um .app: usa um LaunchAgent deste binário.")
                }
            }
            SettingsCard(title: "Vibração") {
                Toggle("Vibrar ao passar o mouse", isOn: $settings.hoverHaptic)
                Picker("", selection: $settings.hapticStrength) {
                    ForEach(HapticStrength.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!settings.hoverHaptic)
            }
            SettingsCard(title: "Acessibilidade") {
                Text("Reduzir movimento")
                Picker("", selection: $settings.motion) {
                    ForEach(MotionPreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Caption("Troca saltos e molas por transições simples.")
            }
            SettingsCard(title: "Avisos e terminal") {
                Toggle("Aviso de resposta pronta", isOn: $settings.finishBanner)
                HStack {
                    Text("Duração")
                    Slider(value: $settings.bannerSeconds, in: 2...10, step: 0.5)
                        .disabled(!settings.finishBanner)
                    Text(String(format: "%.1f s", settings.bannerSeconds))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 40, alignment: .trailing)
                }
                Stepper(value: $settings.terminalFontSize, in: 10...20, step: 1) {
                    Text("Fonte do terminal: \(Int(settings.terminalFontSize)) pt")
                }
            }
        }
    }
}

/// Lays blocks out two per row at one fixed size. A row with a single block
/// puts it in the middle, and the whole group is centred in the page — so a
/// page with one block (or three) never looks lopsided.
struct CardGridLayout: Layout {
    /// Where each of `count` blocks goes inside `size`.
    static func frames(count: Int, in size: CGSize,
                       cardHeight: CGFloat = SettingsLayout.cardHeight,
                       spacing: CGFloat = SettingsLayout.spacing) -> [CGRect] {
        guard count > 0 else { return [] }
        let cardWidth = (size.width - spacing) / 2
        let rows = (count + 1) / 2
        let totalHeight = CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing
        let top = (size.height - totalHeight) / 2
        return (0..<count).map { index in
            let row = index / 2
            let inRow = min(2, count - row * 2)
            let x = inRow == 1 ? (size.width - cardWidth) / 2 : CGFloat(index % 2) * (cardWidth + spacing)
            return CGRect(x: x, y: top + CGFloat(row) * (cardHeight + spacing), width: cardWidth, height: cardHeight)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 440, height: proposal.height ?? SettingsLayout.pageHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = Self.frames(count: subviews.count, in: bounds.size)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

/// The page dots: the current page is a bright pill, the others dim dots; tap
/// one to jump there.
private struct PageRail: View {
    @Binding var pageID: SettingsPage.ID?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SettingsPage.allCases) { item in
                let selected = item.id == pageID
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { pageID = item.id }
                } label: {
                    Capsule()
                        .fill(.white.opacity(selected ? 0.95 : 0.3))
                        .frame(width: 6, height: selected ? 18 : 6)
                        .frame(width: 20, height: selected ? 26 : 14)      // comfortable hit area
                        .contentShape(Rectangle())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Every card shares one size so the grid reads as a clean 2×2.
enum SettingsLayout {
    static let cardHeight: CGFloat = 138
    static let spacing: CGFloat = 10
    /// One page = two rows of cards.
    static let pageHeight: CGFloat = cardHeight * 2 + spacing
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .frame(height: SettingsLayout.cardHeight)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NotchTheme.tileFill)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotchTheme.hairline, lineWidth: 1))
        }
    }
}

struct Caption: View {
    let text: String
    var color: Color = .white.opacity(0.4)
    init(_ text: String, color: Color = .white.opacity(0.4)) { self.text = text; self.color = color }

    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

/// The app's mark and name, tiny, in the corner of the settings panel.
private struct AppBadge: View {
    private static let mark: NSImage? = {
        guard let url = AppResources.url(forResource: "AxiosMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let mark = Self.mark {
                    Image(nsImage: mark).resizable().scaledToFit()
                } else {
                    Image(systemName: "asterisk")
                }
            }
            .frame(width: 12, height: 12)
            Text("Axios Notch")
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
        .padding(.trailing, 6)
        .accessibilityElement(children: .combine)
    }
}
