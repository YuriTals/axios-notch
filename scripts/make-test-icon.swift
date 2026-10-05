import AppKit
import Foundation

// Native vector drawing, rendered at each icon size. Does not modify the production icon.
let manager = FileManager.default
let root = URL(fileURLWithPath: manager.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/TestAppIcon.iconset")
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let sign = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 150, yRadius: 150)
    NSColor(calibratedRed: 1, green: 0.79, blue: 0.06, alpha: 1).setFill()
    sign.fill()
    let rim = NSBezierPath(roundedRect: NSRect(x: 119, y: 119, width: 786, height: 786), xRadius: 118, yRadius: 118)
    NSColor(calibratedWhite: 0.08, alpha: 1).setStroke()
    rim.lineWidth = 15
    rim.stroke()
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: 512, y: 830))
    triangle.line(to: NSPoint(x: 325, y: 488))
    triangle.line(to: NSPoint(x: 699, y: 488))
    triangle.close()
    triangle.lineJoinStyle = .round
    triangle.lineWidth = 30
    triangle.stroke()
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 488, y: 593, width: 48, height: 133), xRadius: 16, yRadius: 16).fill()
    NSBezierPath(ovalIn: NSRect(x: 488, y: 529, width: 48, height: 48)).fill()
    for (text, y, fontSize) in [("BUILD", 324.0, 115.0), ("DE TESTE", 203.0, 96.0)] {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
                                                       .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1)]
        let width = (text as NSString).size(withAttributes: attributes).width
        (text as NSString).draw(at: NSPoint(x: (1024 - width) / 2, y: y), withAttributes: attributes)
    }
    return bitmap.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(512).write(to: root.appendingPathComponent("build/test-icon-preview.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Packaging/TestAppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(EXIT_FAILURE) }
print("Created Packaging/TestAppIcon.icns and build/test-icon-preview.png")
