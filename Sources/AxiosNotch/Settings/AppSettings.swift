import AppKit
import Combine
import SwiftUI

/// The app's own accent colour: settings controls, the Terminal tile and the
/// terminal's "answer ready" dot. Claude and Codex keep their brand colours.
enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, blue, green, purple, pink, gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orange: return tr("Laranja", "Orange")
        case .blue: return tr("Azul", "Blue")
        case .green: return tr("Verde", "Green")
        case .purple: return tr("Roxo", "Purple")
        case .pink: return tr("Rosa", "Pink")
        case .gray: return tr("Cinza", "Gray")
        }
    }

    var color: Color {
        switch self {
        case .orange: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .blue: return Color(red: 0.33, green: 0.58, blue: 0.96)
        case .green: return Color(red: 0.30, green: 0.78, blue: 0.50)
        case .purple: return Color(red: 0.66, green: 0.50, blue: 0.96)
        case .pink: return Color(red: 0.95, green: 0.44, blue: 0.64)
        case .gray: return Color(red: 0.66, green: 0.68, blue: 0.72)
        }
    }
}

/// How the notch treats motion (bouncing dots, springs, pulses).
enum MotionPreference: String, CaseIterable, Identifiable {
    case system, reduce, full
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return tr("Sistema", "System")
        case .reduce: return tr("Reduzir", "Reduce")
        case .full: return "Normal"
        }
    }
}

/// Hover vibration strength: how many haptic taps make up one bump. The
/// public API only has light patterns, so a burst is the way to be firmer.
enum HapticStrength: Int, CaseIterable, Identifiable {
    case soft = 1, medium = 3, strong = 5
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .soft: return tr("Suave", "Soft")
        case .medium: return tr("Médio", "Medium")
        case .strong: return tr("Forte", "Strong")
        }
    }
}

/// User preferences, persisted in `UserDefaults`. One shared instance; views
/// observe it and non-view code reads it directly.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private var applyingLogin = false

    @Published var launchAtLogin: Bool {
        didSet { if !applyingLogin { applyLaunchAtLogin() } }
    }
    /// Why the last launch-at-login change failed, if it did.
    @Published private(set) var loginError: String?

    @Published var language: LanguageChoice {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            Localization.current = language.resolved()
        }
    }

    @Published var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }

    @Published var motion: MotionPreference { didSet { defaults.set(motion.rawValue, forKey: "motion") } }
    @Published var hoverHaptic: Bool { didSet { defaults.set(hoverHaptic, forKey: "hoverHaptic") } }
    @Published var hapticStrength: HapticStrength { didSet { defaults.set(hapticStrength.rawValue, forKey: "hapticStrength") } }
    /// A short system sound when an answer is ready or a tool is waiting. Off by default.
    @Published var soundOnNotice: Bool { didSet { defaults.set(soundOnNotice, forKey: "soundOnNotice") } }
    @Published var soundChoice: SoundChoice { didSet { defaults.set(soundChoice.rawValue, forKey: "soundChoice") } }
    @Published var finishBanner: Bool { didSet { defaults.set(finishBanner, forKey: "finishBanner") } }
    @Published var bannerSeconds: Double { didSet { defaults.set(bannerSeconds, forKey: "bannerSeconds") } }
    @Published var terminalFont: FontChoice {
        didSet {
            defaults.set(terminalFont.rawValue, forKey: "terminalFont")
            TerminalSessionStore.shared.refreshFonts()
        }
    }
    @Published var terminalTheme: TerminalTheme {
        didSet {
            defaults.set(terminalTheme.rawValue, forKey: "terminalTheme")
            TerminalSessionStore.shared.refreshThemes()
        }
    }
    @Published var terminalFontSize: Double {
        didSet {
            defaults.set(terminalFontSize, forKey: "terminalFontSize")
            TerminalSessionStore.shared.refreshFonts()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = LoginItem.isEnabled
        let chosenLanguage = defaults.string(forKey: "language").flatMap(LanguageChoice.init) ?? .system
        language = chosenLanguage
        Localization.current = chosenLanguage.resolved()
        accent = defaults.string(forKey: "accent").flatMap(AccentChoice.init) ?? .orange
        motion = defaults.string(forKey: "motion").flatMap(MotionPreference.init) ?? .system
        hoverHaptic = defaults.object(forKey: "hoverHaptic") as? Bool ?? true
        hapticStrength = (defaults.object(forKey: "hapticStrength") as? Int).flatMap(HapticStrength.init) ?? .strong
        soundOnNotice = defaults.object(forKey: "soundOnNotice") as? Bool ?? false
        soundChoice = defaults.string(forKey: "soundChoice").flatMap(SoundChoice.init) ?? .glass
        finishBanner = defaults.object(forKey: "finishBanner") as? Bool ?? true
        bannerSeconds = defaults.object(forKey: "bannerSeconds") as? Double ?? 4.5
        terminalFontSize = defaults.object(forKey: "terminalFontSize") as? Double ?? 13
        terminalFont = defaults.string(forKey: "terminalFont").flatMap(FontChoice.init) ?? .auto
        terminalTheme = defaults.string(forKey: "terminalTheme").flatMap(TerminalTheme.init) ?? .standard
    }

    /// Whether to tone motion down, honoring the macOS accessibility setting
    /// unless the user picked explicitly.
    var reduceMotion: Bool {
        Self.resolveReduceMotion(preference: motion, systemReduces: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static func resolveReduceMotion(preference: MotionPreference, systemReduces: Bool) -> Bool {
        switch preference {
        case .system: return systemReduces
        case .reduce: return true
        case .full: return false
        }
    }

    private func applyLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(launchAtLogin)
            loginError = nil
        } catch {
            loginError = tr("Não foi possível alterar: \(error.localizedDescription)", "Couldn't change: \(error.localizedDescription)")
            applyingLogin = true
            launchAtLogin = LoginItem.isEnabled
            applyingLogin = false
        }
    }
}

/// Animation choices that respect the reduce-motion setting.
enum NotchMotion {
    static func spring(response: Double, damping: Double = 1) -> Animation {
        AppSettings.shared.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: response, dampingFraction: damping)
    }

    static var hover: Animation {
        AppSettings.shared.reduceMotion ? .easeOut(duration: 0.12) : .bouncy.speed(1.2)
    }
}
