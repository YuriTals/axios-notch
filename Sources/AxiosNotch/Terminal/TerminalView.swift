import SwiftUI
import SwiftTerm

/// Bridges SwiftTerm's `LocalProcessTerminalView` (a real VT100 emulator with
/// its own PTY) into SwiftUI. It starts the provider's CLI once, the first
/// time the view is created; SwiftUI updates don't restart the process.
struct TerminalRepresentable: NSViewRepresentable {
    /// `nil` starts a clean shell instead of a provider CLI.
    let provider: AgentProvider?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.font = TerminalFont.resolve()
        let (executable, args) = PTYSession.launchArguments(for: provider)
        view.startProcess(executable: executable, args: args)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
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
