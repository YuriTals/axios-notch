import XCTest
@testable import AxiosNotch

final class AppSettingsTests: XCTestCase {
    func testReduceMotionFollowsSystemUnlessChosen() {
        XCTAssertTrue(AppSettings.resolveReduceMotion(preference: .system, systemReduces: true))
        XCTAssertFalse(AppSettings.resolveReduceMotion(preference: .system, systemReduces: false))
        XCTAssertTrue(AppSettings.resolveReduceMotion(preference: .reduce, systemReduces: false))
        XCTAssertFalse(AppSettings.resolveReduceMotion(preference: .full, systemReduces: true))
    }

    func testSettingsPersistAcrossInstances() {
        let suite = "axios-notch-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.hapticStrength, .strong)      // defaults
        XCTAssertTrue(first.finishBanner)
        first.hapticStrength = .soft
        first.finishBanner = false
        first.bannerSeconds = 7
        first.motion = .reduce

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.hapticStrength, .soft)
        XCTAssertFalse(second.finishBanner)
        XCTAssertEqual(second.bannerSeconds, 7)
        XCTAssertEqual(second.motion, .reduce)
    }

    func testLaunchAgentPlistRunsAtLoadWithoutStartingNow() throws {
        let data = try LoginItem.launchAgentPlist(executable: "/Applications/Axios Notch.app/Contents/MacOS/AxiosNotch")
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertEqual(plist?["Label"] as? String, LoginItem.label)
        XCTAssertEqual(plist?["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist?["ProgramArguments"] as? [String], ["/Applications/Axios Notch.app/Contents/MacOS/AxiosNotch"])
    }
}

final class AccentTests: XCTestCase {
    func testAccentDefaultsToOrangeAndPersists() {
        let suite = "axios-accent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.accent, .orange)
        first.accent = .purple
        XCTAssertEqual(AppSettings(defaults: defaults).accent, .purple)

        defaults.set("not-a-colour", forKey: "accent")                 // junk falls back
        XCTAssertEqual(AppSettings(defaults: defaults).accent, .orange)
    }

    func testEveryChoiceHasAUniqueNameAndColour() {
        XCTAssertEqual(Set(AccentChoice.allCases.map(\.label)).count, AccentChoice.allCases.count)
        XCTAssertEqual(Set(AccentChoice.allCases.map { "\($0.color)" }).count, AccentChoice.allCases.count)
        // The default keeps the colour the app always had.
        XCTAssertEqual("\(AccentChoice.orange.color)", "\(NotchTheme.claudeAccent)")
    }
}
