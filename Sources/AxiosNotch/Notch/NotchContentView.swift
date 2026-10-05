import AppKit
import SwiftUI

/// SwiftUI's `Image(_:bundle:)` only resolves Asset Catalog entries, not loose
/// files in a resource bundle, so a `.process()`-ed PNG has to be loaded via
/// `NSImage` instead.
private let axiosMark: NSImage? = {
    guard let url = AppResources.url(forResource: "AxiosMark", withExtension: "png") else { return nil }
    return NSImage(contentsOf: url)
}()

struct NotchContentView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject var usageStore: AgentUsageStore
    @ObservedObject private var sessions = TerminalSessionStore.shared
    @ObservedObject private var settings = AppSettings.shared

    private var isOpen: Bool { controller.state != .closed }

    private var shape: NotchShape {
        let radii = isOpen ? NotchWindowController.openRadii : NotchWindowController.closedRadii
        return NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom)
    }

    /// One black surface whose size and corner radii spring between states —
    /// the notch and the panel are a single continuous shape. Readable
    /// content is padded below the camera housing so none of it renders
    /// where it would be invisible.
    var body: some View {
        surface
            .frame(width: controller.surfaceSize.width, height: controller.surfaceSize.height, alignment: .top)
            // The panel itself must merge with the physical camera housing;
            // depth belongs to the cards, never to the notch background.
            .background { panelBackground }
            .overlay(alignment: .top) { closeStrip }
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: (isOpen || controller.isHovering) ? .black.opacity(0.6) : .clear, radius: 10)
            .contentShape(shape)
            .onHover { controller.setHovering($0) }
            .animation(NotchMotion.spring(response: 0.42, damping: 0.9), value: controller.banner)
            .animation(NotchMotion.spring(response: isOpen ? 0.42 : 0.45), value: controller.state)
            .animation(NotchMotion.hover, value: controller.isHovering)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var glassOpen: Bool {
        if #available(macOS 26.0, *) { return settings.glassActive && isOpen }
        return false
    }

    /// Black by default. With the Liquid Glass look the open body is translucent,
    /// but the strip around the physical notch stays black and fades softly into it.
    /// The layers are always in the tree and only change opacity, so they resize with
    /// the surface while it springs open and shut (swapping views left a ghost).
    private var panelBackground: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(glassOpen ? 0 : 1)
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.35))
                .environment(\.colorScheme, .dark)
                .opacity(glassOpen ? 1 : 0)
            // Solid black over the physical notch, then a soft fade into the glass.
            VStack(spacing: 0) {
                Color.black.frame(height: controller.notchStripSize.height)
                LinearGradient(colors: [.black, .black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
            }
            .opacity(glassOpen ? 1 : 0)
            .allowsHitTesting(false)
        }
    }

    /// While open, the strip where the physical notch sits is a tap target
    /// that closes the panel — the same spot that opened it.
    @ViewBuilder
    private var closeStrip: some View {
        if isOpen {
            Color.clear
                .frame(width: controller.notchStripSize.width, height: controller.notchStripSize.height)
                .contentShape(Rectangle())
                .onTapGesture { controller.collapse() }
        }
    }

    private var surface: some View {
        VStack(spacing: 0) {
            stateSurface
            if isOpen && BuildChannel.isTest {
                TestBuildBadge().frame(height: NotchWindowController.testFooterHeight)
            }
        }
    }

    @ViewBuilder
    private var stateSurface: some View {
        switch controller.state {
        case .closed:
            closedView
        case .picker:
            NotchPickerView(controller: controller, usageStore: usageStore)
                .padding(.horizontal, NotchWindowController.openRadii.top)
                .padding(.top, controller.notchStripSize.height)
                .frame(width: controller.openSize(for: controller.state).width,
                       height: controller.openSize(for: controller.state).height - NotchWindowController.testFooterHeight, alignment: .top)
                .transition(.opacity)
        case .drop:
            NotchDropView(controller: controller)
                .padding(.horizontal, NotchWindowController.openRadii.top)
                .padding(.top, controller.notchStripSize.height)
                .frame(width: controller.openSize(for: controller.state).width,
                       height: controller.openSize(for: controller.state).height - NotchWindowController.testFooterHeight, alignment: .top)
                .transition(.opacity)
        case .settings:
            NotchSettingsView(controller: controller, usageStore: usageStore)
                .padding(.horizontal, NotchWindowController.openRadii.top)
                .padding(.top, controller.notchStripSize.height)
                .frame(width: controller.openSize(for: controller.state).width,
                       height: controller.openSize(for: controller.state).height - NotchWindowController.testFooterHeight, alignment: .top)
                .transition(.opacity)
        case .usage(let provider):
            NotchUsageView(controller: controller, provider: provider, summary: usageStore.summaries[provider], limits: usageStore.limits[provider] ?? .loading, forecasts: usageStore.forecasts, refreshFailure: usageStore.limitFailures[provider])
                .padding(.horizontal, NotchWindowController.openRadii.top)
                .padding(.top, controller.notchStripSize.height)
                .frame(width: controller.openSize(for: controller.state).width,
                       height: controller.openSize(for: controller.state).height - NotchWindowController.testFooterHeight, alignment: .top)
                .transition(.opacity)
        case .terminal(let tool):
            TerminalPanelView(tool: tool, onClose: { controller.closeTerminal() })
                .padding(.horizontal, NotchWindowController.openRadii.top)
                .padding(.top, controller.notchStripSize.height)
                .frame(width: controller.openSize(for: controller.state).width,
                       height: controller.openSize(for: controller.state).height - NotchWindowController.testFooterHeight, alignment: .top)
                .transition(.opacity)
        }
    }

    private var closedView: some View {
        VStack(spacing: 0) {
            closedCore
                .frame(width: controller.notchStripSize.width, height: controller.notchStripSize.height)
            if let notice = controller.banner {
                NoticeBanner(notice: notice)
                    .frame(height: NotchWindowController.bannerHeight)
                    .contentShape(Rectangle())
                    // Jump straight to the terminal that just answered.
                    .onTapGesture { controller.activate(notice) }
                    .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { controller.toggleExpanded() }
    }

    private var closedCore: some View {
        HStack(spacing: 6) {
            Group {
                if BuildChannel.isTest {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        .help("BUILD DE TESTE")
                } else if let axiosMark {
                    Image(nsImage: axiosMark)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "terminal")
                }
            }
            .frame(width: 14, height: 14)
            Text(BuildChannel.isTest ? "TESTE" : "Axios")
                .font(.caption)
                .foregroundStyle(BuildChannel.isTest ? .yellow : .white.opacity(0.7))
            ClosedToolStatus()
            // Visible without opening the notch: answering, or answers waiting.
            if sessions.anyWaiting {
                WaitingBadge(size: 14)
            } else if sessions.anyWorking {
                BouncingDots(dot: 3)
            } else if sessions.totalUnread > 0 {
                UnreadBadge(count: sessions.totalUnread, size: 14)
            }
        }
        .animation(NotchMotion.spring(response: 0.3, damping: 0.7), value: sessions.totalUnread)
    }
}

private struct ClosedToolStatus: View {
    @ObservedObject private var sessions = TerminalSessionStore.shared
    var body: some View {
        HStack(spacing: 4) {
            ForEach([Tool.agent(.claude), .agent(.codex), .antigravity], id: \.id) { tool in
                Circle().fill(sessions.isWaiting(tool) ? Color.orange : sessions.isWorking(tool) ? NotchTheme.accent(for: tool) : .white.opacity(0.22))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel(tr("Status das ferramentas", "Tool status"))
    }
}

/// "Answer ready" announcement shown below the notch: who answered.
private struct NoticeBanner: View {
    let notice: NotchNotice
    private var tint: Color { NotchTheme.accent(for: notice.tool) }

    /// Amber for "getting close", red for "almost out"; otherwise the tool's colour.
    private var dotColor: Color {
        switch notice.level {
        case .info: return tint
        case .warning: return Color(red: 0.97, green: 0.68, blue: 0.25)
        case .critical: return Color(red: 0.95, green: 0.33, blue: 0.30)
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ToolGlyph(tool: notice.tool, size: 16)
            HStack(spacing: 5) {
                Text(notice.phrase)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if let project = notice.project {
                    Text("· \(project)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Circle().fill(dotColor).frame(width: 5, height: 5)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("Abre o terminal", "Opens the terminal"))
    }
}
