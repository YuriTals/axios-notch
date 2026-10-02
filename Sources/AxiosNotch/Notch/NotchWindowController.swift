import AppKit
import Combine
import QuartzCore
import SwiftUI

enum NotchState: Equatable {
    case closed
    /// "Active tools" — pick Claude, Codex or the terminal.
    case picker
    /// A file is being dragged to the notch: pick the chat to add it to.
    case drop
    /// Preferences.
    case settings
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
    @Published private(set) var banner: NotchNotice?
    static let bannerHeight: CGFloat = 34
    static let bannerMinWidth: CGFloat = 270
    /// Wider when the banner also names the project.
    static let bannerProjectWidth: CGFloat = 350
    private var bannerDismiss: DispatchWorkItem?
    private var finishObserver: AnyCancellable?
    private var alertObserver: AnyCancellable?

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
    private let usageSize = CGSize(width: 460, height: 278)
    // header (26) + gap (12) + two cards + gap + bottom padding
    private let settingsSize = CGSize(width: 560, height: 26 + 12 + SettingsLayout.pageHeight + 18)
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
        if state == .closed {
            // The body hugs the notch; the ears add `top` radius on each side.
            var size = CGSize(width: closedSize.width + Self.closedRadii.top * 2, height: closedSize.height)
            if isHovering {
                size.width += hoverGrowth.width
                size.height += hoverGrowth.height
            }
            if banner != nil {
                size.height += Self.bannerHeight
                size.width = max(size.width, banner?.project == nil ? Self.bannerMinWidth : Self.bannerProjectWidth)
            }
            return size
        }
        return openSize(for: state)
    }

    /// The final size of an open state. Its content is laid out at exactly
    /// this size from the first frame and merely revealed by the growing
    /// surface; letting content follow the animated frame made tiles squeeze
    /// and the terminal reflow (and resize its PTY) on every frame.
    func openSize(for state: NotchState) -> CGSize {
        switch state {
        case .closed: return surfaceSize
        case .picker, .drop: return CGSize(width: pickerSize.width, height: closedSize.height + pickerSize.height)
        case .usage: return CGSize(width: usageSize.width, height: closedSize.height + usageSize.height)
        case .settings: return CGSize(width: settingsSize.width, height: closedSize.height + settingsSize.height)
        case .terminal: return terminalSize
        }
    }

    /// Fixed and large enough for the biggest state plus its shadow. The
    /// window is never resized when the notch opens or closes: resizing it
    /// made the content ride the moving bottom edge for a frame (a visible
    /// hop). Instead the window ignores the mouse everywhere except over the
    /// surface, so its transparent area never swallows clicks.
    private var windowSize: CGSize {
        CGSize(width: terminalSize.width + shadowInset.width * 2, height: terminalSize.height + shadowInset.height)
    }

    private var localMouseMonitor: Any?
    private var moveMonitors: [Any] = []

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

        alertObserver = usageStore.alerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alert in
                self?.announce(NotchNotice(provider: alert.provider, project: nil, phrase: alert.message,
                                           level: alert.severity, action: .openUsage))
            }

        finishObserver = TerminalSessionStore.shared.$lastFinish
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notice in self?.announce(notice) }

        setWindowFrame()
        updateMousePassthrough()
        panel.orderFrontRegardless()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleClickOutsideWindow()
        }
        // Follow the mouse so the window only takes events while it is over the
        // surface; everywhere else clicks fall through to the apps below (and
        // reach the global monitor above, which closes the notch).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in self?.updateMousePassthrough() }) {
            moveMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }) {
            moveMonitors.append(local)
        }
        // Files being dragged toward the notch (the events come from whichever app
        // started the drag, so only the global monitor sees them).
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] _ in self?.handleFileDrag() }) {
            moveMonitors.append(drag)
        }
        if let release = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in self?.fileDragEnded() }) {
            moveMonitors.append(release)
        }
        // Clicks on the panel's own transparent margin (the shadow ring) land
        // in our window, so the global monitor never sees them.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window === self.panel, self.isOutsideSurface(event.locationInWindow) {
                self.collapse()
            }
            return event
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
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        moveMonitors.forEach { NSEvent.removeMonitor($0) }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        geometry = NotchGeometry.current()
        setWindowFrame()
        updateMousePassthrough()
    }

    /// While closed, hovering nudges the capsule a little larger and gives a
    /// haptic tap (Force Touch trackpads only) — just enough to say
    /// "there's something here", without committing to opening it.
    func setHovering(_ isInside: Bool) {
        guard isHovering != isInside else { return }
        isHovering = isInside
        if isInside, AppSettings.shared.hoverHaptic { playHoverHaptic() }
    }

    /// The public haptic API only offers three light patterns, so a single tap
    /// is easy to miss. A quick burst of taps reads as one stronger bump.
    private func playHoverHaptic() {
        let performer = NSHapticFeedbackManager.defaultPerformer
        for i in 0..<AppSettings.shared.hapticStrength.rawValue {
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

    func showSettings() {
        panel.orderFrontRegardless()
        setState(.settings)
    }

    /// Clicking a banner: an answer opens its terminal, a limit warning opens
    /// that tool's usage.
    func activate(_ notice: NotchNotice) {
        switch notice.action {
        case .openTerminal:
            // Land on the exact tab that answered.
            if let id = notice.sessionID { TerminalSessionStore.shared.select(id: id) }
            openTerminal(for: notice.provider)
        case .openUsage:
            if let provider = notice.provider { showUsage(for: provider) } else { showPicker() }
        }
    }

    // MARK: Dragging files to the notch

    private var dragCheckedChange = -1
    private var dragIsFiles = false

    /// Called on every drag movement anywhere on screen.
    private func handleFileDrag() {
        let drag = NSPasteboard(name: .drag)
        // Reading the pasteboard on every movement is wasteful; do it once per drag.
        if drag.changeCount != dragCheckedChange {
            dragCheckedChange = drag.changeCount
            dragIsFiles = !FileDrag.fileURLs(in: drag).isEmpty
        }
        let action = FileDragRules.action(
            isFileDrag: dragIsFiles, pointer: NSEvent.mouseLocation, notch: geometry.frame,
            openSurface: state == .drop ? surfaceRect(slack: 0) : nil,
            isDropOpen: state == .drop, isIdle: state == .closed)
        switch action {
        case .open:
            panel.orderFrontRegardless()
            setState(.drop)
            updateMousePassthrough()
        case .close:
            setState(.closed)
        case .none:
            if state == .drop { updateMousePassthrough() }     // the window must accept the drop while the pointer is on it
        }
    }

    /// The mouse button was released somewhere. If nothing took the drop, close.
    private func fileDragEnded() {
        dragIsFiles = false
        guard state == .drop else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.state == .drop else { return }
            self.setState(.closed)
        }
    }

    /// Files were dropped on a tool: open its chat and add them.
    func attach(_ urls: [URL], to provider: AgentProvider?) {
        guard !urls.isEmpty else { return }
        openTerminal(for: provider)
        TerminalSessionStore.shared.attach(paths: urls.map(\.path), to: provider)
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
        // Make sure the tool has a tab to show (the first one is created here,
        // never from inside the view).
        TerminalSessionStore.shared.ensureSelected(provider)
        if case .terminal = state {} else { stateBeforeTerminal = state }
        setState(.terminal(provider))
    }

    func closeTerminal() {
        setState(stateBeforeTerminal == .closed ? .picker : stateBeforeTerminal)
    }

    /// Shows the "answer ready" banner for a few seconds, only while closed —
    /// an open panel already has the user's attention.
    private func announce(_ notice: NotchNotice) {
        // Limit warnings are always on; only the "answer ready" banner can be turned off.
        let enabled = notice.action == .openUsage || AppSettings.shared.finishBanner
        guard state == .closed, enabled else { return }
        bannerDismiss?.cancel()
        banner = notice
        updateMousePassthrough()
        let dismiss = DispatchWorkItem { [weak self] in
            self?.banner = nil
            self?.updateMousePassthrough()
        }
        bannerDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.shared.bannerSeconds, execute: dismiss)
    }

    private func setState(_ newState: NotchState) {
        guard newState != state else { return }
        if newState != .closed {
            bannerDismiss?.cancel()
            banner = nil
        }
        state = newState
        // Dropping needs a lower window level; everything else wants the high one.
        panel.level = newState == .drop ? NotchPanel.dropLevel : NotchPanel.restingLevel
        updateMousePassthrough()
        if case .terminal = state {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// A click that reached another app. Usually that means "click outside to
    /// close", but if the pointer jumped onto the surface without a move event
    /// (so the window was still ignoring the mouse) treat it as a click on it.
    private func handleClickOutsideWindow() {
        if surfaceArea.contains(NSEvent.mouseLocation) {
            updateMousePassthrough()
            if state == .closed { toggleExpanded() }
        } else {
            collapse()
        }
    }

    /// Screen-space rectangle of the surface, optionally with some slack.
    private func surfaceRect(slack: CGFloat) -> CGRect {
        let surface = surfaceSize
        return CGRect(
            x: geometry.frame.midX - surface.width / 2 - slack,
            y: geometry.frame.maxY - surface.height - slack,
            width: surface.width + slack * 2,
            height: surface.height + slack * 2
        )
    }

    private var surfaceArea: CGRect { surfaceRect(slack: 8) }

    private func setWindowFrame() {
        let size = windowSize
        panel.setFrame(CGRect(
            x: geometry.frame.midX - size.width / 2,
            y: geometry.frame.maxY - size.height,
            width: size.width,
            height: size.height
        ), display: true)
    }

    /// The window takes mouse events only while the pointer is over the
    /// surface (with a few points of slack for the hover growth and shadow).
    private func updateMousePassthrough() {
        let mouse = NSEvent.mouseLocation
        let inside = surfaceArea.contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        // Hover is derived from the pointer too: while the window ignores the
        // mouse, SwiftUI's onHover never hears the pointer enter.
        setHovering(surfaceRect(slack: 0).contains(mouse))
    }

    /// Is a click (in window coordinates) outside the visible surface?
    private func isOutsideSurface(_ point: CGPoint) -> Bool {
        let window = panel.frame.size
        let surface = surfaceSize
        let left = (window.width - surface.width) / 2
        return point.x < left || point.x > left + surface.width || point.y < window.height - surface.height
    }
}
