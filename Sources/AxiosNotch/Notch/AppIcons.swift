import SwiftUI

/// The three tool icons, drawn in code to match the reference artwork:
/// Claude's pixel mascot, Codex's gradient cloud with a prompt, and the
/// macOS-style Terminal tile. All scale to whatever `size` they're given.

/// Claude's mascot on a 10×8 pixel grid: wide body, side arms, two eyes and
/// two legs with a gap between them.
struct ClaudeMascot: View {
    var color: Color = NotchTheme.claudeAccent

    var body: some View {
        Canvas { context, size in
            let cols = 10.0, rows = 8.0
            let unit = min(size.width / cols, size.height / rows)
            let ox = (size.width - unit * cols) / 2
            let oy = (size.height - unit * rows) / 2
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
                Path(CGRect(x: ox + x * unit, y: oy + y * unit, width: w * unit, height: h * unit))
            }
            context.fill(rect(1, 0, 8, 6), with: .color(color))   // body
            context.fill(rect(0, 2, 10, 2), with: .color(color))  // arms
            context.fill(rect(2, 6, 2, 2), with: .color(color))   // legs
            context.fill(rect(6, 6, 2, 2), with: .color(color))
            context.fill(rect(2, 2, 1, 1), with: .color(.black))  // eyes
            context.fill(rect(7, 2, 1, 1), with: .color(.black))
        }
        .aspectRatio(10.0 / 8.0, contentMode: .fit)
    }
}

/// Antigravity's mark: a soft arch (a bell-shaped peak with a hollow underneath and two
/// feet that fade out), blue overall with green blooming at the top left and red at the
/// top right. The outline is traced from the official artwork on a 768 × 768 canvas and
/// drawn as a vector, so it stays sharp at any size.
struct AntigravityMark: View {
    typealias P = (x: Double, y: Double)

    /// Clockwise from the left tip: up the outer left edge, over the peak, down the
    /// outer right edge, round the right foot and back along the inner arch.
    static let outline: [P] = [
        (118, 620), (134, 587), (158, 557), (176, 527), (190, 497), (202, 467), (212, 437), (222, 407),
        (230, 377), (239, 347), (247, 317), (256, 287), (266, 257), (278, 227), (293, 197), (316, 167),
        (340, 147), (362, 139), (384, 136),
        (410, 142), (430, 150), (453, 167), (475, 197), (490, 227), (502, 257), (512, 287), (521, 317),
        (529, 347), (538, 377), (547, 407), (556, 437), (566, 467), (578, 497), (592, 527), (610, 557),
        (635, 587), (651, 617), (650, 626), (640, 631), (624, 629),
        (596, 617), (561, 587), (536, 557), (516, 527), (498, 497), (481, 467), (458, 437), (432, 418),
        (408, 407), (384, 403), (358, 407), (335, 418), (311, 437), (289, 467), (271, 497), (253, 527),
        (233, 557), (207, 587), (173, 617), (150, 630), (130, 630),
    ]

    /// The region the outline occupies inside the 768 canvas.
    static let bounds = (minX: 117.0, maxX: 652.0, minY: 135.0, maxY: 632.0)

    /// A smooth closed path through the outline (curves through the midpoints).
    static func path(scale: Double, origin: CGPoint) -> Path {
        let pts = outline.map { CGPoint(x: origin.x + ($0.x - bounds.minX) * scale, y: origin.y + ($0.y - bounds.minY) * scale) }
        var path = Path()
        let n = pts.count
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n { path.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i]) }
        path.closeSubpath()
        return path
    }

    static let blue = Color(red: 0.26, green: 0.53, blue: 0.98)
    static let green = Color(red: 0.55, green: 0.74, blue: 0.27)
    static let red = Color(red: 0.93, green: 0.30, blue: 0.27)
    static let olive = Color(red: 0.80, green: 0.66, blue: 0.27)

    var body: some View {
        Canvas { context, size in
            let width = Self.bounds.maxX - Self.bounds.minX, height = Self.bounds.maxY - Self.bounds.minY
            let scale = Double(min(size.width, size.height)) / max(width, height)
            let origin = CGPoint(x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2)
            let shape = Self.path(scale: scale, origin: origin)
            let box = CGRect(x: origin.x, y: origin.y, width: width * scale, height: height * scale)

            context.drawLayer { layer in
                layer.fill(shape, with: .color(Self.blue))
                layer.clip(to: shape)
                // Green blooms at the upper left, red at the upper right, with a warm olive
                // where they meet at the peak; blue takes over from the middle down.
                func bloom(_ color: Color, _ x: Double, _ y: Double, _ radius: Double) -> GraphicsContext.Shading {
                    .radialGradient(Gradient(stops: [.init(color: color, location: 0), .init(color: color.opacity(0.7), location: 0.3), .init(color: color.opacity(0), location: 1)]),
                                    center: CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y),
                                    startRadius: 0, endRadius: box.width * radius)
                }
                layer.fill(Path(box), with: bloom(Self.green, 0.27, 0.20, 0.42))
                layer.fill(Path(box), with: bloom(Self.red, 0.76, 0.12, 0.36))
                layer.fill(Path(box), with: bloom(Self.olive, 0.50, 0.0, 0.20))
                // The feet fade out toward their tips.
                layer.blendMode = .destinationOut
                layer.fill(Path(box), with: .linearGradient(
                    Gradient(colors: [.clear, .white.opacity(0.62)]),
                    startPoint: CGPoint(x: box.midX, y: box.minY + box.height * 0.80),
                    endPoint: CGPoint(x: box.midX, y: box.maxY)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A rounded eight-lobed cloud.
private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let lobe = radius * 0.36
        let distance = radius - lobe
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - distance, y: center.y - distance, width: distance * 2, height: distance * 2))
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            let c = CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
            path.addEllipse(in: CGRect(x: c.x - lobe, y: c.y - lobe, width: lobe * 2, height: lobe * 2))
        }
        return path
    }
}

/// The `>_` prompt, in unit coordinates so each icon can place it.
private struct PromptMark: Shape {
    /// Chevron box and underscore, all in 0...1 of the rect.
    var chevron: CGRect
    var underscore: (from: CGPoint, to: CGPoint)

    func path(in rect: CGRect) -> Path {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(chevron.minX, chevron.minY))
        path.addLine(to: point(chevron.maxX, chevron.midY))
        path.addLine(to: point(chevron.minX, chevron.maxY))
        path.move(to: point(underscore.from.x, underscore.from.y))
        path.addLine(to: point(underscore.to.x, underscore.to.y))
        return path
    }
}

/// Codex: blue-violet gradient cloud with a white prompt.
struct CodexCloud: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                CloudShape()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.69, green: 0.66, blue: 1.0), Color(red: 0.44, green: 0.58, blue: 1.0), Color(red: 0.20, green: 0.27, blue: 1.0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                PromptMark(
                    chevron: CGRect(x: 0.30, y: 0.38, width: 0.12, height: 0.25),
                    underscore: (CGPoint(x: 0.51, y: 0.62), CGPoint(x: 0.69, y: 0.62))
                )
                .stroke(.white, style: StrokeStyle(lineWidth: side * 0.055, lineCap: .round, lineJoin: .round))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Terminal: light bezel, black ring, dark screen, white prompt top-left.
struct TerminalIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.23, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.78, green: 0.89, blue: 0.93), Color(red: 0.52, green: 0.53, blue: 0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                RoundedRectangle(cornerRadius: s * 0.20, style: .continuous)
                    .fill(.black)
                    .padding(s * 0.035)
                RoundedRectangle(cornerRadius: s * 0.13, style: .continuous)
                    .fill(Color(white: 0.15))
                    .padding(s * 0.10)
                PromptMark(
                    chevron: CGRect(x: 0.25, y: 0.25, width: 0.10, height: 0.12),
                    underscore: (CGPoint(x: 0.38, y: 0.405), CGPoint(x: 0.49, y: 0.405))
                )
                .stroke(.white, style: StrokeStyle(lineWidth: s * 0.04, lineCap: .square, lineJoin: .miter))
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
