import SwiftUI
import SwiftTerm

/// Bridges SwiftTerm's `LocalProcessTerminalView` (a real VT100 emulator with
/// its own PTY) into SwiftUI. The terminal itself comes from
/// `TerminalSessionStore`, so closing and reopening the panel, or switching
/// tabs, returns to the same running session.
struct TerminalRepresentable: NSViewRepresentable {
    let key: SessionKey

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // The store always has the view for a selected key; the placeholder
        // only exists so a stale key can never crash the panel.
        let view = TerminalSessionStore.shared.view(for: key) ?? LocalProcessTerminalView(frame: .zero)
        view.removeFromSuperview()
        TerminalSessionStore.shared.didShow(key)
        return view
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // The key isn't available here; the store clears by view identity.
        TerminalSessionStore.shared.didHide(view: nsView)
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

/// The monospaced fonts developers use most in terminals. Only the ones that
/// are installed are offered (SF Mono is the system's own and always is).
enum FontChoice: String, CaseIterable, Identifiable {
    case auto, sfMono, menlo, monaco, jetbrains, firaCode, sourceCode, hack, cascadia, plex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return tr("Automática (Nerd Font)", "Automatic (Nerd Font)")
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .monaco: return "Monaco"
        case .jetbrains: return "JetBrains Mono"
        case .firaCode: return "Fira Code"
        case .sourceCode: return "Source Code Pro"
        case .hack: return "Hack"
        case .cascadia: return "Cascadia Code"
        case .plex: return "IBM Plex Mono"
        }
    }

    /// Family names to try, most specific first. A Nerd Font build comes first
    /// so prompt icons (Starship, Powerlevel10k…) keep drawing.
    var families: [String] {
        switch self {
        case .auto: return TerminalFont.nerdPreferred
        case .sfMono: return []                                     // system font
        case .menlo: return ["Menlo"]
        case .monaco: return ["Monaco"]
        case .jetbrains: return ["JetBrainsMono Nerd Font Mono", "JetBrains Mono"]
        case .firaCode: return ["FiraCode Nerd Font Mono", "Fira Code"]
        case .sourceCode: return ["SauceCodePro Nerd Font Mono", "Source Code Pro"]
        case .hack: return ["Hack Nerd Font Mono", "Hack"]
        case .cascadia: return ["CaskaydiaCove Nerd Font Mono", "Cascadia Code"]
        case .plex: return ["BlexMono Nerd Font Mono", "IBM Plex Mono"]
        }
    }

    /// Whether the choice can be used: the system fonts always can, and so can
    /// anything shipped inside the app (see `FontRegistry`).
    func isAvailable(in families: [String]) -> Bool {
        self == .auto || self == .sfMono || self.families.contains(where: families.contains)
    }

    /// True for the choices whose font file is bundled with the app, so they
    /// work on a Mac that has nothing installed.
    var isBundled: Bool {
        families.contains(where: FontRegistry.bundledFamilies.contains)
    }

    static func available(families: [String] = FontRegistry.availableFamilies()) -> [FontChoice] {
        allCases.filter { $0.isAvailable(in: families) }
    }
}

/// Resolves the chosen font. Prompt themes draw icons from Nerd Font glyph
/// ranges that normal fonts lack ("?" boxes), so any chosen font gets a Nerd
/// Font as a fallback for those glyphs when one is installed.
enum TerminalFont {
    static var size: CGFloat { CGFloat(AppSettings.shared.terminalFontSize) }
    static let nerdPreferred = ["FiraCode Nerd Font Mono", "JetBrainsMono Nerd Font Mono", "MesloLGS Nerd Font Mono", "Hack Nerd Font Mono"]

    static func resolve(choice: FontChoice = AppSettings.shared.terminalFont, size: CGFloat = TerminalFont.size,
                        families: [String] = FontRegistry.availableFamilies()) -> NSFont {
        let nerd = nerdFamily(in: families)

        if choice == .auto {
            if let nerd, let font = font(family: nerd, size: size) { return font }
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        let base: NSFont
        if choice == .sfMono {
            base = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        } else if let family = choice.families.first(where: families.contains), let found = font(family: family, size: size) {
            base = found
        } else {
            return resolve(choice: .auto, size: size, families: families)
        }
        // Already a Nerd Font, or none installed: nothing to add.
        let baseIsNerd = base.familyName?.localizedCaseInsensitiveContains("Nerd") ?? false
        guard let nerd, !baseIsNerd else { return base }
        return withNerdFallback(base, nerdFamily: nerd, size: size)
    }

    private static func nerdFamily(in families: [String]) -> String? {
        let candidates = nerdPreferred
            + families.filter { $0.localizedCaseInsensitiveContains("Nerd Font Mono") }
            + families.filter { $0.localizedCaseInsensitiveContains("Nerd Font") && !$0.localizedCaseInsensitiveContains("Propo") }
        return candidates.first(where: families.contains)
    }

    private static func font(family: String, size: CGFloat) -> NSFont? {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }

    private static func withNerdFallback(_ base: NSFont, nerdFamily: String, size: CGFloat) -> NSFont {
        guard let nerd = font(family: nerdFamily, size: size) else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [nerd.fontDescriptor]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

/// The terminal panel: a tab bar for this tool's sessions on top, the
/// selected terminal below.
struct TerminalPanelView: View {
    let tool: Tool
    let onClose: () -> Void
    @ObservedObject private var store = TerminalSessionStore.shared

    private var selected: SessionKey? { store.selectedKey(for: tool) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ToolGlyph(tool: tool, size: 14)
                SessionTabs(tool: tool)
                Spacer(minLength: 4)
                // Copying "the last answer" needs a screen layout we know; not for unknown tools.
                if !tool.isCustom { CopyAnswerButton(tool: tool) }
                OpenFolderButton(tool: tool)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Fechar painel", "Close panel"))
            }
            .padding(8)

            if let selected {
                // `.id` makes switching tabs a fresh representable, so the right
                // terminal is attached and marked as seen.
                TerminalRepresentable(key: selected)
                    .id(selected.id)
            }
        }
        // Last tab ended (`exit`, or closed with ×): nothing left to show.
        .onChange(of: selected) { _, newValue in
            if newValue == nil { onClose() }
        }
    }
}

/// Copies the output since the last Enter to the clipboard, and says so by
/// turning into a checkmark for a moment.
private struct CopyAnswerButton: View {
    let tool: Tool
    @ObservedObject private var store = TerminalSessionStore.shared
    @State private var copied = false
    @State private var nothing = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : (nothing ? "exclamationmark" : "doc.on.doc"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(copied ? Color(red: 0.30, green: 0.85, blue: 0.45) : .white.opacity(nothing ? 0.35 : 0.7))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(tr("Copiar a última resposta", "Copy the last answer"))
        .accessibilityLabel(tr("Copiar a última resposta", "Copy the last answer"))
    }

    private func copy() {
        if let key = store.selectedKey(for: tool), let text = store.lastAnswer(for: key) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } else {
            nothing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { nothing = false }
        }
    }
}

/// Folder icon: show the selected tab's folder in Finder, or open it in an
/// installed editor. The folder is read when you click, so it is always the
/// one the shell is in right now.
private struct OpenFolderButton: View {
    let tool: Tool
    @ObservedObject private var store = TerminalSessionStore.shared

    private func folder() -> String? {
        store.selectedKey(for: tool).flatMap { store.currentDirectory(for: $0) }
    }

    var body: some View {
        Menu {
            Button(tr("Mostrar no Finder", "Show in Finder")) { folder().map(FolderOpener.showInFinder) }
            let editors = EditorCatalog.installed()
            if !editors.isEmpty {
                Divider()
                ForEach(editors) { editor in
                    Button(tr("Abrir no \(editor.name)", "Open in \(editor.name)")) {
                        if let path = folder() { FolderOpener.open(path, in: editor) }
                    }
                }
            }
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Abrir a pasta desta sessão", "Open this session's folder"))
        .accessibilityLabel(tr("Abrir pasta", "Open folder"))
    }
}

/// One chip per open session of this tool, plus "+" to open another.
private struct SessionTabs: View {
    let tool: Tool
    @ObservedObject private var store = TerminalSessionStore.shared

    var body: some View {
        HStack(spacing: 5) {
            // Project folders can change under a shell (`cd`), so refresh the names.
            TimelineView(.periodic(from: .now, by: 2)) { context in
                HStack(spacing: 5) {
                    ForEach(store.keys(for: tool), id: \.id) { key in
                        SessionTab(key: key, isSelected: key == store.selectedKey(for: tool), tick: context.date)
                    }
                    NewSessionButton(tool: tool, tick: context.date)
                }
            }
        }
    }
}

private struct SessionTab: View {
    let key: SessionKey
    let isSelected: Bool
    /// Changes every couple of seconds. The tab's name comes from the shell's
    /// current folder, which no published value announces; a changing input is
    /// what makes SwiftUI re-read it (equal inputs would skip the redraw).
    let tick: Date
    @ObservedObject private var store = TerminalSessionStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(store.title(for: key))
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 110)
            if store.isWaiting(key) {
                WaitingBadge(size: 12)
            } else if store.isWorking(key) {
                BouncingDots(dot: 2.5)
            } else if store.unreadCount(key) > 0 {
                UnreadBadge(count: store.unreadCount(key), size: 12)
            }
            if isSelected || hovering {
                Button { store.close(key) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 12, height: 12)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Encerrar sessão", "End session"))
            }
        }
        .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.6))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(isSelected ? 0.16 : (hovering ? 0.1 : 0.06))))
        .contentShape(Capsule())
        .onTapGesture { store.select(key) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// "+" — a fresh session in the home folder, in the current tab's folder, or in
/// a folder you pick.
private struct NewSessionButton: View {
    let tool: Tool
    /// See `SessionTab.tick`: the current folder changes without any published
    /// value, so a changing input keeps the menu's contents fresh.
    let tick: Date
    @ObservedObject private var store = TerminalSessionStore.shared

    private var atLimit: Bool { store.keys(for: tool).count >= SessionKey.maxPerProvider }

    private var currentFolder: String? {
        guard let key = store.selectedKey(for: tool),
              let path = store.currentDirectory(for: key),
              ProcessDirectory.projectName(forPath: path) != nil else { return nil }
        return path
    }

    var body: some View {
        Menu {
            Button(tr("Nova sessão", "New session")) { store.openSession(tool, directory: nil) }
            if let folder = currentFolder {
                Button(tr("Na mesma pasta (\(ProcessDirectory.projectName(forPath: folder) ?? ""))", "In the same folder (\(ProcessDirectory.projectName(forPath: folder) ?? ""))")) {
                    store.openSession(tool, directory: folder)
                }
            }
            Button(tr("Escolher pasta…", "Choose folder…")) { chooseFolder() }
            let recent = store.recents.suggestions(excluding: Set([currentFolder].compactMap { $0 }))
            if !recent.isEmpty {
                Divider()
                Text(tr("Recentes", "Recent"))
                ForEach(recent, id: \.self) { path in
                    Button(ProcessDirectory.projectName(forPath: path) ?? path) {
                        store.openSession(tool, directory: path)
                    }
                }
                Divider()
                Button(tr("Limpar recentes", "Clear recents")) { store.clearRecents() }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(atLimit ? 0.25 : 0.7))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(atLimit)
        .help(atLimit ? tr("Limite de \(SessionKey.maxPerProvider) sessões", "Limit of \(SessionKey.maxPerProvider) sessions") : tr("Nova sessão", "New session"))
        .accessibilityLabel(tr("Nova sessão", "New session"))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Abrir aqui", "Open here")
        panel.message = tr("Escolha a pasta em que a nova sessão vai começar", "Choose the folder the new session will start in")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { store.openSession(tool, directory: url.path) }
        }
    }
}
