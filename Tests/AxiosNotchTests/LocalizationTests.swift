import XCTest
@testable import AxiosNotch

/// Runs the body with a given language and puts the previous one back.
func withLanguage(_ lang: Lang, _ body: () -> Void) {
    let previous = Localization.current
    Localization.current = lang
    defer { Localization.current = previous }
    body()
}

final class LocalizationTests: XCTestCase {
    func testTrPicksTheCurrentLanguage() {
        withLanguage(.pt) { XCTAssertEqual(tr("Voltar", "Back"), "Voltar") }
        withLanguage(.en) { XCTAssertEqual(tr("Voltar", "Back"), "Back") }
    }

    func testSystemLanguageFollowsMacOS() {
        XCTAssertEqual(LanguageChoice.system.resolved(preferredLanguages: ["pt-BR", "en-US"]), .pt)
        XCTAssertEqual(LanguageChoice.system.resolved(preferredLanguages: ["pt-PT"]), .pt)
        XCTAssertEqual(LanguageChoice.system.resolved(preferredLanguages: ["en-US", "pt-BR"]), .en)
        XCTAssertEqual(LanguageChoice.system.resolved(preferredLanguages: ["ja-JP"]), .en)
        XCTAssertEqual(LanguageChoice.system.resolved(preferredLanguages: []), .en)
        // An explicit choice ignores the system.
        XCTAssertEqual(LanguageChoice.portuguese.resolved(preferredLanguages: ["en-US"]), .pt)
        XCTAssertEqual(LanguageChoice.english.resolved(preferredLanguages: ["pt-BR"]), .en)
    }

    func testChoosingALanguageSwitchesTheInterfaceAndPersists() {
        let suite = "axios-lang-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let previous = Localization.current
        defer { defaults.removePersistentDomain(forName: suite); Localization.current = previous }

        let settings = AppSettings(defaults: defaults)
        settings.language = .english
        XCTAssertEqual(Localization.current, .en)
        XCTAssertEqual(settings.accent.label, "Orange")
        settings.language = .portuguese
        XCTAssertEqual(Localization.current, .pt)
        XCTAssertEqual(settings.accent.label, "Laranja")

        settings.language = .english
        _ = AppSettings(defaults: defaults)                               // a new launch reads it back…
        XCTAssertEqual(Localization.current, .en)                         // …and applies it
        XCTAssertEqual(AppSettings(defaults: defaults).language, .english)
    }

    func testTimeAndAlertTextsAreTranslated() {
        let now = Date()
        withLanguage(.en) {
            XCTAssertEqual(UsageFormat.remaining(until: now.addingTimeInterval(4 * 3600 + 35 * 60 + 5), now: now), "resets in 4h 35min")
            XCTAssertEqual(UsageFormat.ageSuffix(since: now.addingTimeInterval(-12 * 60), now: now), " · 12 min ago")
            XCTAssertEqual(LimitAlert(provider: .claude, window: .fiveHour, kind: .threshold(80), percent: 82.4).message, "Claude: 82% of the 5h window")
            XCTAssertEqual(LimitAlert(provider: .codex, window: .weekly, kind: .threshold(90), percent: 91).message, "Codex: 91% of the weekly limit!")
            XCTAssertEqual(LimitAlert(provider: .codex, window: .weekly, kind: .reset, percent: 0).message, "Codex: weekly limit reset!")
        }
        withLanguage(.pt) {
            XCTAssertEqual(UsageFormat.remaining(until: now.addingTimeInterval(12 * 60 + 5), now: now), "reinicia em 12min")
            XCTAssertEqual(LimitAlert(provider: .claude, window: .fiveHour, kind: .reset, percent: 2).message, "Claude: janela de 5h reiniciou!")
        }
    }

    func testSettingsLabelsFollowTheLanguage() {
        withLanguage(.en) {
            XCTAssertEqual(SettingsPage.general.title, "General")
            XCTAssertEqual(SettingsPage.experience.title, "Experience")
            XCTAssertEqual(SettingsPage.tools.title, "Tools")
            XCTAssertEqual(HapticStrength.strong.label, "Strong")
            XCTAssertEqual(MotionPreference.reduce.label, "Reduce")
            XCTAssertEqual(LanguageChoice.system.label, "System")
        }
        withLanguage(.pt) {
            XCTAssertEqual(SettingsPage.general.title, "Geral")
            XCTAssertEqual(SettingsPage.experience.title, "Experiência")
            XCTAssertEqual(SettingsPage.tools.title, "Ferramentas")
            XCTAssertEqual(HapticStrength.strong.label, "Forte")
            XCTAssertEqual(LanguageChoice.system.label, "Sistema")
        }
    }
}
