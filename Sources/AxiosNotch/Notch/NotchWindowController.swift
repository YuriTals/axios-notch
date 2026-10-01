import AppKit
import QuartzCore
import SwiftUI

enum NotchState: Equatable {
    case closed
    case expanded
    case terminal(AgentProvider)
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    /// Without this, AppKit swallows the very first click on a window that
    /// isn't key/active (which a non-activating accessory-app panel never
    /// becomes through normal means) — it uses that click only to bring the
    /// window forward and never delivers it to the view as a real mouseDown.
    /// Since every click on this panel is effectively "the first one", every
    /// click would otherwise be silently dropped.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
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
    private var isHovering = false

    private let hoverGrowth = CGSize(width: 10, height: 5)
    private let expandedSize = CGSize(width: 380, height: 480)
    private let terminalSize = CGSize(width: 640, height: 420)

    /// Hugs the real notch exactly when there is one — same width and height
    /// as the camera housing, so the closed capsule fills it edge to edge —
    /// and falls back to a fixed pill size on external/non-notch displays.
    private var closedSize: CGSize {
        geometry.hasPhysicalNotch ? geometry.frame.size : CGSize(width: 170, height: 30)
    }

    /// The width/height every state's window shares at its very top edge —
    /// deliberately never wider than the physical notch (or the fallback
    /// capsule), so an expanded panel can never paint over real menu bar
    /// icons to either side of it. Wider content only starts below this.
    var notchStripSize: CGSize { closedSize }

    init(usageStore: AgentUsageStore) {
        geometry = NotchGeometry.current()
        panel = NotchPanel(contentRect: CGRect(origin: .zero, size: CGSize(width: 170, height: 30)))
        super.init()

        let content = NotchContentView(controller: self, usageStore: usageStore)
        let hostingView = NotchHostingView(rootView: content)
        hostingView.onHoverChange = { [weak self] isInside in self?.handleHover(isInside) }
        panel.contentView = hostingView

        applyFrame(animate: false)
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
        applyFrame(animate: false)
    }

    /// While closed, hovering nudges the capsule a little larger and gives a
    /// light haptic tap (Force Touch trackpads only) — just enough to say
    /// "there's something here", without committing to opening it.
    private func handleHover(_ isInside: Bool) {
        guard state == .closed, isHovering != isInside else { return }
        isHovering = isInside
        if isInside {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        applyFrame(animate: true)
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
        applyFrame(animate: true)
    }

    private func applyFrame(animate: Bool) {
        var size: CGSize
        switch state {
        case .closed: size = closedSize
        case .expanded: size = expandedSize
        case .terminal: size = terminalSize
        }
        if state == .closed && isHovering {
            size.width += hoverGrowth.width
            size.height += hoverGrowth.height
        }

        let origin = CGPoint(
            x: geometry.frame.midX - size.width / 2,
            y: geometry.frame.maxY - size.height
        )
        let frame = CGRect(origin: origin, size: size)

        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }

        if case .terminal = state {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
