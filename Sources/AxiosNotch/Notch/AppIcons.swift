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
