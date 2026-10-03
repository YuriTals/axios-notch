import AppKit
import SwiftTerm

/// A colour scheme for the notch terminal.
enum TerminalTheme: String, CaseIterable, Identifiable {
    case standard, dracula, nord, solarized, tokyo, gruvbox

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return tr("Padrão", "Default")
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .solarized: return "Solarized"
        case .tokyo: return "Tokyo Night"
        case .gruvbox: return "Gruvbox"
        }
    }

    /// `#rrggbb` strings: background, foreground, then the 16 ANSI colours
    /// (black … white, then the bright row). `nil` means "SwiftTerm's own".
    struct Palette {
        let background: String
        let foreground: String
        let ansi: [String]?
    }

    var palette: Palette {
        switch self {
        case .standard:
            return Palette(background: "#000000", foreground: "#e5e5e5", ansi: nil)
        case .dracula:
            return Palette(background: "#282a36", foreground: "#f8f8f2", ansi: [
                "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"])
        case .nord:
            return Palette(background: "#2e3440", foreground: "#d8dee9", ansi: [
                "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"])
        case .solarized:
            return Palette(background: "#002b36", foreground: "#93a1a1", ansi: [
                "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#586e75", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"])
        case .tokyo:
            return Palette(background: "#1a1b26", foreground: "#c0caf5", ansi: [
                "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"])
        case .gruvbox:
            return Palette(background: "#282828", foreground: "#ebdbb2", ansi: [
                "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"])
        }
    }

    func apply(to view: LocalProcessTerminalView) {
        let p = palette
        view.installColors(p.ansi.map { $0.map { Self.terminalColor(hex: $0) } } ?? Color.defaultInstalledColors)
        let opacity = AppSettings.shared.effectiveTerminalOpacity
        view.nativeBackgroundColor = NSColor(hex: p.background).withAlphaComponent(opacity)
        // A see-through terminal needs a layer that is not declared opaque.
        view.wantsLayer = true
        view.layer?.isOpaque = opacity >= 1
        view.nativeForegroundColor = NSColor(hex: p.foreground)
    }

    static func terminalColor(hex: String) -> Color {
        let (r, g, b) = rgb(hex)
        return Color(red8: UInt16(r), green8: UInt16(g), blue8: UInt16(b))
    }

    /// `#rrggbb` (or without `#`) to 0...255 components; bad input is black.
    static func rgb(_ hex: String) -> (Int, Int, Int) {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return (0, 0, 0) }
        return ((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let (r, g, b) = TerminalTheme.rgb(hex)
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
