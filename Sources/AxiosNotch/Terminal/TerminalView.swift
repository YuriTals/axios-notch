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

/// Prompt themes (Starship, Powerlevel10k…) draw icons from Nerd Font glyph
/// ranges that normal fonts lack, which shows up as "?" boxes. Prefer an
/// installed Nerd Font *Mono* variant (fixed-width glyphs, so columns line
/// up), then any Nerd Font, then the system monospaced font.
enum TerminalFont {
    static var size: CGFloat { CGFloat(AppSettings.shared.terminalFontSize) }
    private static let preferredFamilies = ["FiraCode Nerd Font Mono", "JetBrainsMono Nerd Font Mono", "MesloLGS Nerd Font Mono", "Hack Nerd Font Mono"]

    static func resolve(size: CGFloat = TerminalFont.size) -> NSFont {
        let families = NSFontManager.shared.availableFontFamilies
        let candidates = preferredFamilies
            + families.filter { $0.localizedCaseInsensitiveContains("Nerd Font Mono") }
            + families.filter { $0.localizedCaseInsensitiveContains("Nerd Font") && !$0.localizedCaseInsensitiveContains("Propo") }
        for family in candidates where families.contains(family) {
            if let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// The terminal panel: a tab bar for this tool's sessions on top, the
/// selected terminal below.
struct TerminalPanelView: View {
    let provider: AgentProvider?
    let onClose: () -> Void
    @ObservedObject private var store = TerminalSessionStore.shared

    private var selected: SessionKey? { store.selectedKey(for: provider) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let provider {
                    ProviderGlyph(provider: provider, size: 14)
                } else {
                    TerminalIcon().frame(width: 14, height: 14)
                }
                SessionTabs(provider: provider)
                Spacer(minLength: 4)
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

/// One chip per open session of this tool, plus "+" to open another.
private struct SessionTabs: View {
    let provider: AgentProvider?
    @ObservedObject private var store = TerminalSessionStore.shared

    var body: some View {
        HStack(spacing: 5) {
            // Project folders can change under a shell (`cd`), so refresh the names.
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                HStack(spacing: 5) {
                    ForEach(store.keys(for: provider), id: \.id) { key in
                        SessionTab(key: key, isSelected: key == store.selectedKey(for: provider))
                    }
                }
            }
            NewSessionButton(provider: provider)
        }
    }
}

private struct SessionTab: View {
    let key: SessionKey
    let isSelected: Bool
    @ObservedObject private var store = TerminalSessionStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(store.title(for: key))
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 110)
            if store.isWorking(key) {
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
    let provider: AgentProvider?
    @ObservedObject private var store = TerminalSessionStore.shared

    private var atLimit: Bool { store.keys(for: provider).count >= SessionKey.maxPerProvider }

    private var currentFolder: String? {
        guard let key = store.selectedKey(for: provider),
              let path = store.currentDirectory(for: key),
              ProcessDirectory.projectName(forPath: path) != nil else { return nil }
        return path
    }

    var body: some View {
        Menu {
            Button(tr("Nova sessão", "New session")) { store.openSession(provider, directory: nil) }
            if let folder = currentFolder {
                Button(tr("Na mesma pasta (\(ProcessDirectory.projectName(forPath: folder) ?? ""))", "In the same folder (\(ProcessDirectory.projectName(forPath: folder) ?? ""))")) {
                    store.openSession(provider, directory: folder)
                }
            }
            Button(tr("Escolher pasta…", "Choose folder…")) { chooseFolder() }
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
            DispatchQueue.main.async { store.openSession(provider, directory: url.path) }
        }
    }
}
