import AppKit

/// Where the panel should sit: hugging the physical notch cutout when one
/// exists, or a centered capsule at the top of the menu bar otherwise
/// (external displays, older MacBooks).
struct NotchGeometry {
    let frame: CGRect
    let hasPhysicalNotch: Bool

    static func current(for screen: NSScreen? = NSScreen.main) -> NotchGeometry {
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
