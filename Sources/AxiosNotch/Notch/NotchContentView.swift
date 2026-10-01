import AppKit
import SwiftUI

/// SwiftUI's `Image(_:bundle:)` only resolves Asset Catalog entries, not loose
/// files in a resource bundle, so a `.process()`-ed PNG has to be loaded via
/// `NSImage` instead.
private let axiosMark: NSImage? = {
    guard let url = Bundle.module.url(forResource: "AxiosMark", withExtension: "png") else { return nil }
    return NSImage(contentsOf: url)
}()

struct NotchContentView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject var usageStore: AgentUsageStore

    /// Closed, this hugs the physical notch exactly. Open, the black
    /// background fills the whole shape with no gap or transparent hole —
    /// continuous from the very top, like the notch and the panel are one
    /// piece — but the actual readable content (tabs, text) is padded down
    /// internally so none of it renders under the physical camera housing,
    /// where it would just be invisible.
    var body: some View {
        Group {
            switch controller.state {
            case .closed:
                closedView
                    .frame(width: controller.notchStripSize.width, height: controller.notchStripSize.height)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            case .expanded, .terminal:
                card
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var card: some View {
        switch controller.state {
        case .expanded:
            NotchDashboardView(controller: controller, usageStore: usageStore)
                .padding(.top, controller.notchStripSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        case .terminal(let provider):
            TerminalPanelView(provider: provider, onClose: { controller.closeTerminal() })
                .padding(.top, controller.notchStripSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
        case .closed:
            EmptyView()
        }
    }

    private var closedView: some View {
        HStack(spacing: 6) {
            Group {
                if let axiosMark {
                    Image(nsImage: axiosMark)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "terminal")
                }
            }
            .frame(width: 14, height: 14)
            Text("Axios")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.toggleExpanded() }
    }
}
