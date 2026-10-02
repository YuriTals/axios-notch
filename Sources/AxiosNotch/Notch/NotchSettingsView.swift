import AppKit
import SwiftUI

/// The settings pages. Each is a screenful of cards; the panel scrolls between
/// them with snap (trackpad / wheel) and a rail of icons on the right to jump,
/// like the iOS 26 Control Center.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, experience, tools

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .experience: return "sparkles"
        case .tools: return "terminal.fill"
        }
    }

    var title: String {
        switch self {
        case .general: return tr("Geral", "General")
        case .experience: return tr("Experiência", "Experience")
        case .tools: return tr("Ferramentas", "Tools")
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
    @ObservedObject var usageStore: AgentUsageStore
    @State private var feedbackNote: String?
    @State private var notificationNote: String?
    @State private var newToolName = ""
    @State private var newToolCommand = ""
    private var page: SettingsPage { SettingsPage.allCases.first { $0.id == pageID } ?? .general }

    private let railWidth: CGFloat = 26

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                IconButton(systemName: "chevron.left") { controller.showPicker() }
                    .accessibilityLabel(tr("Voltar", "Back"))
                // Always "Ajustes": the page you are on is shown by the dots, not by the title.
                Text(tr("Ajustes", "Settings"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
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
        .tint(settings.accent.color)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func pageContent(_ page: SettingsPage) -> some View {
        switch page {
        case .general: generalPage
        case .experience: experiencePage
        case .tools: toolsPage
        }
    }

    /// Appearance, interaction and notices are kept together: they change how
    /// Axios feels, rather than its data or registered programs.
    private var experiencePage: some View {
        CardGridLayout {
            SettingsCard(title: "Design") {
                HStack(spacing: 0) {
                    ForEach(AccentChoice.allCases) { choice in
                        AccentSwatch(choice: choice, isSelected: settings.accent == choice) { settings.accent = choice }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(tr("Cor de destaque", "Accent color"))
                HStack(spacing: 8) {
                    Text(tr("Tema", "Theme"))
                    Picker("", selection: $settings.terminalTheme) {
                        ForEach(TerminalTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: 4) {
                    Text(tr("Fonte", "Font"))
                    Picker("", selection: $settings.terminalFont) {
                        ForEach(FontChoice.available()) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    Stepper("", value: $settings.terminalFontSize, in: 10...20, step: 1)
                        .labelsHidden()
                    Text("\(Int(settings.terminalFontSize))")
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 18)
                }
            }
            SettingsCard(title: tr("Interação", "Interaction")) {
                Toggle(tr("Vibrar ao passar o mouse", "Vibrate on hover"), isOn: $settings.hoverHaptic)
                Picker("", selection: $settings.hapticStrength) {
                    ForEach(HapticStrength.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!settings.hoverHaptic)
                Text(tr("Reduzir movimento", "Reduce motion"))
                Picker("", selection: $settings.motion) {
                    ForEach(MotionPreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            noticesCard
        }
    }

    /// Startup and language belong to the app itself, so they get a quiet,
    /// focused page instead of competing with visual and notification controls.
    private var generalPage: some View {
        CardGridLayout {
            SettingsCard(title: tr("Inicialização", "Startup")) {
                Toggle(tr("Iniciar ao fazer login", "Launch at login"), isOn: $settings.launchAtLogin)
                if let error = settings.loginError {
                    Caption(error, color: Color(red: 0.95, green: 0.45, blue: 0.4))
                } else if !LoginItem.isBundled {
                    Caption(tr("Fora de um .app: usa um LaunchAgent deste binário.", "Outside an .app: uses a LaunchAgent for this binary."))
                }
                Toggle(tr("Reabrir abas ao iniciar", "Reopen tabs on launch"), isOn: $settings.reopenTabs)
            }
            SettingsCard(title: tr("Idioma", "Language")) {
                Caption(tr("Escolha o idioma da interface.", "Choose the interface language."))
                Text(tr("Idioma", "Language"))
                Picker("", selection: $settings.language) {
                    ForEach(LanguageChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            SettingsCard(title: tr("Feedback", "Feedback")) {
                Caption(tr("Abre seu app de e-mail com uma mensagem pronta e dados técnicos: versões, preferências e estado. Nunca tokens, conversas ou pastas.", "Opens your mail app with a ready message and technical details: versions, preferences and status. Never tokens, conversations or folders."))
                Button(action: sendFeedback) {
                    Text(tr("Enviar feedback", "Send feedback")).frame(maxWidth: .infinity)
                }
                if let feedbackNote { Caption(feedbackNote) }
            }
        }
    }

    private func sendFeedback() {
        let snapshot = FeedbackReport.snapshot(settings: settings, usage: usageStore, sessions: TerminalSessionStore.shared)
        let intro = tr("Escreva aqui seu comentário, sugestão ou problema:", "Write your comment, suggestion or problem here:")
        let body = FeedbackReport.body(snapshot, intro: intro)
        let subject = "Axios Notch \(snapshot.version) · feedback"
        if let url = FeedbackReport.mailtoURL(subject: subject, body: body), NSWorkspace.shared.open(url) {
            feedbackNote = nil
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            feedbackNote = tr("Nenhum app de e-mail encontrado. O relatório foi copiado; envie para \(FeedbackReport.recipient).", "No mail app found. The report was copied; send it to \(FeedbackReport.recipient).")
        }
    }

    private var toolsPage: some View {
        CardGridLayout {
            toolsListCard
            addToolCard
            suggestionsCard
        }
    }

    private var noticesCard: some View {
        SettingsCard(title: tr("Avisos", "Notices")) {
            Toggle(tr("Aviso de resposta pronta", "Answer-ready notice"), isOn: $settings.finishBanner)
            Toggle(tr("Notificação do macOS", "macOS notification"), isOn: $settings.systemNotification)
                .onChange(of: settings.systemNotification) { _, on in
                    guard on else { return }
                    SystemNotifier.shared.requestAuthorization { access in
                        switch access {
                        case .allowed:
                            notificationNote = nil
                        case .denied:
                            settings.systemNotification = false
                            notificationNote = tr("Desativadas para o Axios Notch. Ative em Ajustes do Sistema › Notificações.", "Turned off for Axios Notch. Enable it in System Settings › Notifications.")
                        case .unsupported:
                            settings.systemNotification = false
                            notificationNote = tr("Só funciona no app instalado (.app).", "Only works in the installed app (.app).")
                        case .failed(let message):
                            settings.systemNotification = false
                            notificationNote = message
                        }
                    }
                }
            if let notificationNote { Caption(notificationNote, color: Color(red: 0.95, green: 0.45, blue: 0.4)) }
            HStack(spacing: 6) {
                Toggle(tr("Som", "Sound"), isOn: $settings.soundOnNotice)
                Picker("", selection: $settings.soundChoice) {
                    ForEach(SoundChoice.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 84)
                .disabled(!settings.soundOnNotice)
                .onChange(of: settings.soundChoice) { _, choice in NoticeSound.play(choice) }
            }
            HStack {
                Text(tr("Duração", "Duration"))
                Slider(value: $settings.bannerSeconds, in: 2...10, step: 0.5)
                    .disabled(!settings.finishBanner)
                Text(String(format: "%.1f s", settings.bannerSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, alignment: .trailing)
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

/// One round colour choice; the chosen one has a ring.
private struct AccentSwatch: View {
    let choice: AccentChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(choice.color)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2).padding(-4))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .animation(.easeOut(duration: 0.12), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
    /// Enough separation for the rounded corners to read as individual cards.
    static let spacing: CGFloat = 14
    /// Two rows of cards.
    static let gridHeight: CGFloat = cardHeight * 2 + spacing
    /// One page: the grid plus a little air above and below, so the borders of
    /// a neighbouring page never peek in at the seam while scrolling.
    static let pageHeight: CGFloat = gridHeight + 6
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
            content()
        }
        // The padding must stay inside CardGridLayout's proposed bounds. If the
        // frame comes first, padding makes each card 24 pt wider, so neighbours
        // overlap along their shared edge.
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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


// MARK: Tool cards (the user's extra commands, next to the built-in Claude, Codex, Antigravity, Terminal)

extension NotchSettingsView {
    private var canAddTool: Bool {
        settings.customTools.count < CustomTool.maxCount && CustomTool(name: newToolName, command: newToolCommand).isValid
    }

    var toolsListCard: some View {
        SettingsCard(title: tr("Minhas ferramentas", "My tools")) {
            if settings.customTools.isEmpty {
                Caption(tr("Além do Claude, Codex, Antigravity e Terminal. Cadastre um comando ou use uma sugestão.", "Besides Claude, Codex, Antigravity and Terminal. Register a command or pick a suggestion."))
            } else {
                ForEach(settings.customTools) { tool in
                    HStack(spacing: 7) {
                        ToolGlyph(tool: .custom(tool.id), size: 16)
                        Text(tool.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(tool.command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 2)
                        Button { settings.removeCustomTool(id: tool.id) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("Remover \(tool.name)", "Remove \(tool.name)"))
                    }
                }
            }
            Spacer(minLength: 0)
            Caption(tr("\(settings.customTools.count) de \(CustomTool.maxCount)", "\(settings.customTools.count) of \(CustomTool.maxCount)"))
        }
    }

    var addToolCard: some View {
        SettingsCard(title: tr("Adicionar", "Add")) {
            TextField(tr("Nome (ex.: Aider)", "Name (e.g. Aider)"), text: $newToolName)
                .textFieldStyle(.roundedBorder)
            TextField(tr("Comando (ex.: aider)", "Command (e.g. aider)"), text: $newToolCommand)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTool)
            Button(action: addTool) {
                Text(tr("Adicionar", "Add")).frame(maxWidth: .infinity)
            }
            .disabled(!canAddTool)
        }
    }

    var suggestionsCard: some View {
        SettingsCard(title: tr("Sugestões", "Suggestions")) {
            ForEach(CustomTool.presets, id: \.name) { preset in
                let added = settings.customTools.contains { $0.name.lowercased() == preset.name.lowercased() }
                Button {
                    settings.addCustomTool(name: preset.name, command: preset.command)
                } label: {
                    HStack {
                        Text(preset.name)
                        Spacer()
                        Image(systemName: added ? "checkmark" : "plus").font(.system(size: 10, weight: .bold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(added || settings.customTools.count >= CustomTool.maxCount)
                .opacity(added ? 0.45 : 1)
            }
        }
    }

    private func addTool() {
        guard canAddTool, settings.addCustomTool(name: newToolName, command: newToolCommand) else { return }
        newToolName = ""
        newToolCommand = ""
    }
}
