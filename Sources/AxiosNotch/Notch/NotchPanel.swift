import AppKit

/// A borderless, non-activating panel — the same trick Spotlight-style
/// overlays use to accept keyboard/mouse input without stealing focus (or
/// the menu bar) from whatever app is frontmost.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The everyday level, above even the menu bar's own separator.
    static let restingLevel = NSWindow.Level.screenSaver
    /// While a file is being dragged to the notch. macOS does not offer windows
    /// at or above its dragging layer (500) as drop targets, so the panel has to
    /// come down below it — still above the menu bar (24).
    static let dropLevel = NSWindow.Level.popUpMenu

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
        isMovable = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        // .statusBar sits above ordinary app windows but not necessarily
        // above the real menu bar's own chrome (it has a separator/shadow
        // drawn by the system at an even higher level) — .screenSaver is
        // high enough to guarantee this panel always wins that fight.
        level = Self.restingLevel
        // .ignoresCycle keeps it out of Cmd+` / Mission Control's window list
        // — it's a notch overlay, not a window the user should "switch to".
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}
