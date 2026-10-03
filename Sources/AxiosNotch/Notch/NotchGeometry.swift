import AppKit

/// Where the panel should sit: hugging the physical notch cutout when one
/// exists, or a centered capsule at the top of the menu bar otherwise
/// (external displays, older MacBooks).
struct NotchGeometry {
    let frame: CGRect
    let hasPhysicalNotch: Bool

    /// The screen that should carry the panel: the one with the physical notch (the
    /// MacBook's own display, even when an external monitor is the "main" one or
    /// has the focus), otherwise the one with the menu bar.
    static func preferredScreen(in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        preferredIndex(hasNotch: screens.map { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil })
            .map { screens[$0] }
    }

    /// `screens.first` is the menu bar screen, so it is the fallback without a notch.
    static func preferredIndex(hasNotch: [Bool]) -> Int? {
        if let notched = hasNotch.firstIndex(of: true) { return notched }
        return hasNotch.isEmpty ? nil : 0
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Reaching the top edge of a screen is how the user asks for the panel there.
    static func isInTopBand(_ point: CGPoint, of frame: CGRect, band: CGFloat = 24) -> Bool {
        frame.contains(point) && point.y >= frame.maxY - band
    }

    static func current(for screen: NSScreen? = preferredScreen()) -> NotchGeometry {
        guard let screen else {
            return NotchGeometry(frame: .zero, hasPhysicalNotch: false)
        }

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notchWidth = right.minX - left.maxX
            let notchHeight = left.height
            let frame = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - notchHeight,
                width: notchWidth,
                height: notchHeight
            )
            return NotchGeometry(frame: frame, hasPhysicalNotch: true)
        }

        let fallbackSize = CGSize(width: 220, height: 32)
        let frame = CGRect(
            x: screen.frame.midX - fallbackSize.width / 2,
            y: screen.frame.maxY - fallbackSize.height,
            width: fallbackSize.width,
            height: fallbackSize.height
        )
        return NotchGeometry(frame: frame, hasPhysicalNotch: false)
    }
}
