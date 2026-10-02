import SwiftUI
import UniformTypeIdentifiers

/// What the notch shows while a file is being dragged to it: the three tools,
/// and a "+" on the one under the pointer. Dropping adds the file to that
/// tool's chat.
struct NotchDropView: View {
    @ObservedObject var controller: NotchWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Solte para adicionar ao chat", "Drop to add to the chat"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.leading, 4)

            HStack(spacing: 10) {
                ForEach(AgentProvider.allCases) { provider in
                    DropTile(title: provider.displayName, tint: NotchTheme.accent(for: provider)) {
                        ProviderGlyph(provider: provider, size: 30)
                    } onDrop: { urls in controller.attach(urls, to: provider) }
                }
                DropTile(title: "Terminal", tint: NotchTheme.appAccent) {
                    TerminalIcon().frame(width: 32, height: 32)
                } onDrop: { urls in controller.attach(urls, to: nil) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }
}

private struct DropTile<Glyph: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let glyph: () -> Glyph
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            glyph().frame(height: 32)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(targeted ? 1 : 0.8))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background {
            RoundRectangle(targeted: targeted, tint: tint)
        }
        .overlay(alignment: .topTrailing) {
            if targeted { PlusBadge(tint: tint).padding(7).transition(.scale.combined(with: .opacity)) }
        }
        .scaleEffect(targeted && !AppSettings.shared.reduceMotion ? 1.05 : 1)
        .shadow(color: tint.opacity(targeted ? 0.35 : 0), radius: 10)
        .animation(NotchMotion.spring(response: 0.28, damping: 0.7), value: targeted)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            FileDrag.loadFileURLs(from: providers) { urls in if !urls.isEmpty { onDrop(urls) } }
            return true
        }
        .accessibilityLabel(tr("Adicionar ao chat do \(title)", "Add to \(title) chat"))
    }
}

private struct RoundRectangle: View {
    let targeted: Bool
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(targeted ? NotchTheme.tileHoverFill : NotchTheme.tileFill)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(targeted ? tint.opacity(0.9) : NotchTheme.hairline, lineWidth: targeted ? 1.5 : 1)
            }
    }
}

/// The "+" that says "this will be added".
struct PlusBadge: View {
    let tint: Color

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: 18, height: 18)
            .background(Circle().fill(tint))
    }
}
