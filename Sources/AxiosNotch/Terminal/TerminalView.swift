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
        let (executable, args) = PTYSession.launchArguments(for: provider)
        view.startProcess(executable: executable, args: args)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
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
