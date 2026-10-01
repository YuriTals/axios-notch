import AppKit
import QuartzCore
import SwiftUI

enum NotchState: Equatable {
    case closed
    case expanded
    case terminal(AgentProvider)
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Without this, AppKit swallows the very first click on a window that
    /// isn't key/active (which a non-activating accessory-app panel never
    /// becomes through normal means) — it uses that click only to bring the
    /// window forward and never delivers it to the view as a real mouseDown.
    /// Since every click on this panel is effectively "the first one", every
    /// click would otherwise be silently dropped.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the notch panel and drives it through its three states. Sizing and
/// positioning are handled here; `NotchContentView` only reacts to `state`.
final class NotchWindowController: NSObject, ObservableObject {
    @Published private(set) var state: NotchState = .closed
    /// Which provider's dashboard the expanded state is showing.
    @Published private(set) var selectedProvider: AgentProvider = .claude

    private let panel: NotchPanel
    private var geometry: NotchGeometry
    private var globalMouseMonitor: Any?
    private var lastUsedProvider: AgentProvider?
    /// Drives the closed-state hover growth; set from the SwiftUI surface.
    @Published private(set) var isHovering = false

    /// Corner radii for the notch silhouette, closed vs. open.
    static let closedRadii = (top: CGFloat(6), bottom: CGFloat(14))
    static let openRadii = (top: CGFloat(19), bottom: CGFloat(24))

    private let hoverGrowth = CGSize(width: 10, height: 5)
    /// Room around the surface for the drop shadow.
    private let shadowInset = CGSize(width: 24, height: 30)
    /// Landscape, like a widget card — not a tall scrolling panel.
    private let expandedSize = CGSize(width: 640, height: 170)
    private let terminalSize = CGSize(width: 640, height: 420)

    /// Hugs the real notch exactly when there is one — same width and height
    /// as the camera housing, so the closed capsule fills it edge to edge —
    /// and falls back to a fixed pill size on external/non-notch displays.
    private var closedSize: CGSize {
        geometry.hasPhysicalNotch ? geometry.frame.size : CGSize(width: 170, height: 30)
    }

    /// The visible notch surface for the current state. SwiftUI animates this
    /// with a spring; the window itself stays at `windowSize`.
    var surfaceSize: CGSize {
        switch state {
        case .closed:
            // The body hugs the notch; the ears add `top` radius on each side.
            var size = CGSize(width: closedSize.width + Self.closedRadii.top * 2, height: closedSize.height)
            if isHovering {
                size.width += hoverGrowth.width
                size.height += hoverGrowth.height
            }
            return size
        case .expanded: return expandedSize
        case .terminal: return terminalSize
        }
    }

    /// Fixed and large enough for the biggest state plus shadow, so state
    /// changes never have to animate the NSWindow frame.
    private var windowSize: CGSize {
        CGSize(width: terminalSize.width + shadowInset.width * 2, height: terminalSize.height + shadowInset.height)
    }

    /// The width/height every state's window shares at its very top edge —
    /// deliberately never wider than the physical notch (or the fallback
    /// capsule), so an expanded panel can never paint over real menu bar
    /// icons to either side of it. Wider content only starts below this.
    var notchStripSize: CGSize { closedSize }

    init(usageStore: AgentUsageStore) {
        geometry = NotchGeometry.current()
        panel = NotchPanel(contentRect: .zero)
        super.init()

        let content = NotchContentView(controller: self, usageStore: usageStore)
        let hostingView = NotchHostingView(rootView: content)
        panel.contentView = hostingView

        applyFrame()
        panel.orderFrontRegardless()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.collapse()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        geometry = NotchGeometry.current()
        applyFrame()
    }

    /// While closed, hovering nudges the capsule a little larger and gives a
    /// light haptic tap (Force Touch trackpads only) — just enough to say
    /// "there's something here", without committing to opening it.
    func setHovering(_ isInside: Bool) {
        guard isHovering != isInside else { return }
        isHovering = isInside
        if isInside, state == .closed {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    func toggleExpanded() {
        switch state {
        case .closed: setState(.expanded)
        default: collapse()
        }
    }

    func collapse() {
        guard state != .closed else { return }
        setState(.closed)
    }

    /// Hides the panel entirely — used by the menu bar item's Pause action.
    /// Collapses first so resuming always starts from the closed capsule.
    func pause() {
        setState(.closed)
        panel.orderOut(nil)
    }

    func resume() {
        panel.orderFrontRegardless()
    }

    func selectProvider(_ provider: AgentProvider) {
        selectedProvider = provider
    }

    func openTerminal(for provider: AgentProvider?) {
        let resolved = provider ?? lastUsedProvider ?? selectedProvider
        lastUsedProvider = resolved
        selectedProvider = resolved
        setState(.terminal(resolved))
    }

    func closeTerminal() {
        setState(.expanded)
    }

    private func setState(_ newState: NotchState) {
        guard newState != state else { return }
        state = newState
        if case .terminal = state {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func applyFrame() {
        let size = windowSize
        let frame = CGRect(
            x: geometry.frame.midX - size.width / 2,
            y: geometry.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }
}
