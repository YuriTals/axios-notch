import SwiftUI
import SwiftTerm

/// Keeps each terminal alive after its panel closes. SwiftUI destroys a
/// view when its state leaves the screen, which would kill the process and
/// lose the conversation; here the `LocalProcessTerminalView` (and the PTY
/// process behind it) outlives the view and is simply re-attached next time.
/// One session per provider, plus one for the clean shell. A session whose
/// process has exited is dropped, so the next open starts fresh.
final class TerminalSessionStore: ObservableObject {
    static let shared = TerminalSessionStore()

    /// Which sessions have a live process, for the picker's "active" dots.
    @Published private(set) var activeKeys: Set<String> = []

    static func key(for provider: AgentProvider?) -> String { provider?.rawValue ?? "shell" }

    func isActive(_ provider: AgentProvider?) -> Bool { activeKeys.contains(Self.key(for: provider)) }

    private final class Session: LocalProcessTerminalViewDelegate {
        let view = LocalProcessTerminalView(frame: .zero)
        var onExit: (() -> Void)?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [onExit] in onExit?() }
        }
    }

    private var sessions: [String: Session] = [:]

    func view(for provider: AgentProvider?) -> LocalProcessTerminalView {
        let key = Self.key(for: provider)
        if let existing = sessions[key] { return existing.view }

        let session = Session()
        session.view.font = TerminalFont.resolve()
        session.view.processDelegate = session
        session.onExit = { [weak self, weak session] in
            // Only drop it if it is still the current session for this key.
            if let self, let session, self.sessions[key] === session {
                self.sessions[key] = nil
                self.activeKeys.remove(key)
            }
        }
        let (executable, args) = PTYSession.launchArguments(for: provider)
        session.view.startProcess(executable: executable, args: args)
        sessions[key] = session
        // Created during a SwiftUI update, so publish on the next turn.
        DispatchQueue.main.async { [weak self] in self?.activeKeys.insert(key) }
        return session.view
    }
}

/// Bridges SwiftTerm's `LocalProcessTerminalView` (a real VT100 emulator with
/// its own PTY) into SwiftUI. The terminal itself comes from
/// `TerminalSessionStore`, so closing and reopening the panel returns to the
/// same running session.
struct TerminalRepresentable: NSViewRepresentable {
    /// `nil` is the clean shell instead of a provider CLI.
    let provider: AgentProvider?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = TerminalSessionStore.shared.view(for: provider)
        view.removeFromSuperview()
        return view
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
    static let size: CGFloat = 13
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

struct TerminalPanelView: View {
    let provider: AgentProvider?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: provider?.symbolName ?? "terminal")
                    .foregroundStyle(.white.opacity(0.7))
                Text(provider?.displayName ?? "Terminal")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(8)

            TerminalRepresentable(provider: provider)
        }
    }
}
