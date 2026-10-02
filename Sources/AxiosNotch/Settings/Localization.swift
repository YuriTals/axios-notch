import Foundation

/// The two languages the interface speaks.
enum Lang: Equatable {
    case pt, en
}

/// What the user picked in the settings. `system` follows macOS: Portuguese
/// when it is the first preferred language, English otherwise.
enum LanguageChoice: String, CaseIterable, Identifiable {
    case system, portuguese, english

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return tr("Sistema", "System")
        case .portuguese: return "Português"
        case .english: return "English"
        }
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> Lang {
        switch self {
        case .portuguese: return .pt
        case .english: return .en
        case .system: return (preferredLanguages.first ?? "en").lowercased().hasPrefix("pt") ? .pt : .en
        }
    }
}

/// The language currently in force. Plain storage behind a lock so it can be
/// read from any thread (the network code builds error messages off the main
/// thread); `AppSettings` keeps it up to date.
enum Localization {
    private static let lock = NSLock()
    private static var storage: Lang = LanguageChoice.system.resolved()

    static var current: Lang {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

/// Picks the Portuguese or English text for the current language.
/// Interpolated values go in both versions: `tr("há \(n) min", "\(n) min ago")`.
func tr(_ pt: String, _ en: String) -> String {
    Localization.current == .pt ? pt : en
}
