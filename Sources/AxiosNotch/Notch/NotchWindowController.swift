import AppKit
import Combine
import QuartzCore
import SwiftUI

enum NotchState: Equatable {
    case closed
    /// "Active tools" — pick Claude, Codex or the terminal.
    case picker
    /// 5-hour and weekly usage for one provider.
    case usage(AgentProvider)
    /// `nil` is a clean shell; a provider runs that CLI.
    case terminal(AgentProvider?)
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
    /// Set for a few seconds when an answer finishes while the notch is
    /// closed; the closed notch grows downward to announce it.
    @Published private(set) var banner: FinishNotice?
    static let bannerHeight: CGFloat = 34
    static let bannerMinWidth: CGFloat = 220
    private var bannerDismiss: DispatchWorkItem?
    private var finishObserver: AnyCancellable?

    /// Where the terminal's close button returns to.
    private var stateBeforeTerminal: NotchState = .picker

    private let panel: NotchPanel
    private var geometry: NotchGeometry
    private var globalMouseMonitor: Any?
    /// Drives the closed-state hover growth; set from the SwiftUI surface.
    @Published private(set) var isHovering = false

    /// Corner radii for the notch silhouette, closed vs. open.
    static let closedRadii = (top: CGFloat(6), bottom: CGFloat(14))
    static let openRadii = (top: CGFloat(19), bottom: CGFloat(24))

    private let hoverGrowth = CGSize(width: 10, height: 5)
    /// Room around the surface for the drop shadow.
    private let shadowInset = CGSize(width: 24, height: 30)
    /// Content heights below the notch strip; widths include the ears.
    private let pickerSize = CGSize(width: 340, height: 112)
    private let usageSize = CGSize(width: 460, height: 190)
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
            if banner != nil {
                size.height += Self.bannerHeight
                size.width = max(size.width, Self.bannerMinWidth)
            }
            return size
        case .picker: return CGSize(width: pickerSize.width, height: closedSize.height + pickerSize.height)
        case .usage: return CGSize(width: usageSize.width, height: closedSize.height + usageSize.height)
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

        finishObserver = TerminalSessionStore.shared.$lastFinish
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notice in self?.announce(notice) }

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
    /// haptic tap (Force Touch trackpads only) — just enough to say
    /// "there's something here", without committing to opening it.
    func setHovering(_ isInside: Bool) {
        guard isHovering != isInside else { return }
        isHovering = isInside
        if isInside { playHoverHaptic() }
    }

    /// The public haptic API only offers three light patterns, so a single tap
    /// is easy to miss. A quick burst of taps reads as one stronger bump.
    private func playHoverHaptic() {
        let performer = NSHapticFeedbackManager.defaultPerformer
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.03) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
    }

    func toggleExpanded() {
        switch state {
        case .closed: setState(.picker)
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

    func showPicker() {
        setState(.picker)
    }

    func showUsage(for provider: AgentProvider) {
        setState(.usage(provider))
    }

    /// Opens the terminal: running `provider`'s CLI, or a clean shell when
    /// `provider` is nil.
    func openTerminal(for provider: AgentProvider?) {
        if case .terminal = state {} else { stateBeforeTerminal = state }
        setState(.terminal(provider))
    }

    func closeTerminal() {
        setState(stateBeforeTerminal == .closed ? .picker : stateBeforeTerminal)
    }

    /// Shows the "answer ready" banner for a few seconds, only while closed —
    /// an open panel already has the user's attention.
    private func announce(_ notice: FinishNotice) {
        guard state == .closed else { return }
        bannerDismiss?.cancel()
        banner = notice
        let dismiss = DispatchWorkItem { [weak self] in self?.banner = nil }
        bannerDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: dismiss)
    }

    private func setState(_ newState: NotchState) {
        guard newState != state else { return }
        if newState != .closed {
            bannerDismiss?.cancel()
            banner = nil
        }
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
