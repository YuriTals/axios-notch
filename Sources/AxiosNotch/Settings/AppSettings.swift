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
        case .orange: return "Laranja"
        case .blue: return "Azul"
        case .green: return "Verde"
        case .purple: return "Roxo"
        case .pink: return "Rosa"
        case .gray: return "Cinza"
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
        case .system: return "Sistema"
        case .reduce: return "Reduzir"
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
        case .soft: return "Suave"
        case .medium: return "Médio"
        case .strong: return "Forte"
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

    @Published var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }

    @Published var motion: MotionPreference { didSet { defaults.set(motion.rawValue, forKey: "motion") } }
    @Published var hoverHaptic: Bool { didSet { defaults.set(hoverHaptic, forKey: "hoverHaptic") } }
    @Published var hapticStrength: HapticStrength { didSet { defaults.set(hapticStrength.rawValue, forKey: "hapticStrength") } }
    @Published var finishBanner: Bool { didSet { defaults.set(finishBanner, forKey: "finishBanner") } }
    @Published var bannerSeconds: Double { didSet { defaults.set(bannerSeconds, forKey: "bannerSeconds") } }
    @Published var terminalFontSize: Double {
        didSet {
            defaults.set(terminalFontSize, forKey: "terminalFontSize")
            TerminalSessionStore.shared.refreshFonts()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = LoginItem.isEnabled
        accent = defaults.string(forKey: "accent").flatMap(AccentChoice.init) ?? .orange
        motion = defaults.string(forKey: "motion").flatMap(MotionPreference.init) ?? .system
        hoverHaptic = defaults.object(forKey: "hoverHaptic") as? Bool ?? true
        hapticStrength = (defaults.object(forKey: "hapticStrength") as? Int).flatMap(HapticStrength.init) ?? .strong
        finishBanner = defaults.object(forKey: "finishBanner") as? Bool ?? true
        bannerSeconds = defaults.object(forKey: "bannerSeconds") as? Double ?? 4.5
        terminalFontSize = defaults.object(forKey: "terminalFontSize") as? Double ?? 13
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
            loginError = "Não foi possível alterar: \(error.localizedDescription)"
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
