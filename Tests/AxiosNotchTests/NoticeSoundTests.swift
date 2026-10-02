import XCTest
import AppKit
@testable import AxiosNotch

final class NoticeSoundTests: XCTestCase {
    func testEveryOfferedSoundExistsOnThisMac() {
        for choice in SoundChoice.allCases {
            XCTAssertNotNil(NSSound(named: NSSound.Name(choice.systemName)), "missing system sound \(choice.systemName)")
        }
        XCTAssertEqual(SoundChoice.glass.systemName, "Glass")
        XCTAssertEqual(Set(SoundChoice.allCases.map(\.label)).count, SoundChoice.allCases.count)
    }

    func testSoundIsOffByDefaultAndPersists() {
        let suite = "axios-sound-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertFalse(first.soundOnNotice)
        XCTAssertEqual(first.soundChoice, .glass)
        first.soundOnNotice = true
        first.soundChoice = .hero

        let second = AppSettings(defaults: defaults)
        XCTAssertTrue(second.soundOnNotice)
        XCTAssertEqual(second.soundChoice, .hero)
    }

    func testPlaysOnlyWhenEnabled() {
        let suite = "axios-sound2-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        // Off: nothing may start playing.
        NoticeSound.playIfEnabled(settings: settings)
        XCTAssertFalse(NSSound(named: "Glass")?.isPlaying ?? false)

        // On: the sound object really starts.
        let sound = NoticeSound.play(.glass)
        XCTAssertNotNil(sound)
        XCTAssertTrue(sound?.isPlaying ?? false)
        sound?.stop()
    }
}
