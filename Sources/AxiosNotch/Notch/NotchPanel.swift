import AppKit

/// A borderless, non-activating panel — the same trick Spotlight-style
/// overlays use to accept keyboard/mouse input without stealing focus (or
/// the menu bar) from whatever app is frontmost.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init(contentRect: CGRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        // .statusBar sits above ordinary app windows but not necessarily
        // above the real menu bar's own chrome (it has a separator/shadow
        // drawn by the system at an even higher level) — .screenSaver is
        // high enough to guarantee this panel always wins that fight.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
}
