import XCTest
@testable import AxiosNotch

final class WhatsNewTests: XCTestCase {
    private let notes = """
    ## Axios Notch 1.0.2

    **Fixes and improvements**
    - Auto-update with a "What's new" window.

    **Install:** download the `.dmg`.

    **Requirements:** macOS 14+.

    SHA-256 of the `.dmg`: `abc`
    """

    private func makeStore() -> WhatsNewStore {
        WhatsNewStore(defaults: UserDefaults(suiteName: "WhatsNewTests-\(UUID().uuidString)")!)
    }

    private func release(_ version: String) -> ReleaseInfo {
        ReleaseInfo(tag: "v\(version)", version: AppVersion(version)!, notes: notes,
                    pageURL: URL(string: "https://example.com")!, dmgURL: nil, sha256: nil)
    }

    func testCleanKeepsWhatChangedAndDropsTheBoilerplate() {
        let cleaned = WhatsNewStore.clean(notes)
        XCTAssertTrue(cleaned.contains("Fixes and improvements"))
        XCTAssertTrue(cleaned.contains("Auto-update"))
        XCTAssertFalse(cleaned.contains("Install"))
        XCTAssertFalse(cleaned.contains("SHA-256"))
        XCTAssertFalse(cleaned.contains("## "))
    }

    func testShowsOnceOnTheFirstLaunchAfterTheUpdate() {
        let store = makeStore()
        store.remember(release("1.0.2"))
        let entry = store.consume(currentVersion: "1.0.2")
        XCTAssertEqual(entry?.version, AppVersion("1.0.2"))
        XCTAssertTrue(entry?.notes.contains("Auto-update") == true)
        XCTAssertNil(store.consume(currentVersion: "1.0.2"), "must not appear a second time")
    }

    func testNothingToShowWithoutAnUpdate() {
        XCTAssertNil(makeStore().consume(currentVersion: "1.0.2"))
    }

    func testStaleNotesForAnotherVersionAreDiscarded() {
        let store = makeStore()
        store.remember(release("1.0.3"))
        XCTAssertNil(store.consume(currentVersion: "1.0.2"))
        XCTAssertNil(store.consume(currentVersion: "1.0.3"), "the stale entry is cleared, not kept for later")
    }

    func testNotesThatAreAllBoilerplateShowNothing() {
        let store = makeStore()
        let empty = ReleaseInfo(tag: "v1.0.2", version: AppVersion("1.0.2")!, notes: "**Install:** x",
                                pageURL: URL(string: "https://example.com")!, dmgURL: nil, sha256: nil)
        store.remember(empty)
        XCTAssertNil(store.consume(currentVersion: "1.0.2"))
    }

    private let bilingual = """
    <!-- en -->
    ## Axios Notch 1.0.2

    **Fixes and improvements**
    - English line.

    **Install:** download.

    <!-- pt-BR -->
    ## Axios Notch 1.0.2

    **Correções e melhorias**
    - Linha em português.

    **Instalar:** baixe.
    """

    func testPicksTheUsersLanguage() {
        XCTAssertTrue(WhatsNewStore.section(of: bilingual, for: .pt).contains("Linha em português"))
        XCTAssertFalse(WhatsNewStore.section(of: bilingual, for: .pt).contains("English line"))
        XCTAssertTrue(WhatsNewStore.section(of: bilingual, for: .en).contains("English line"))
        XCTAssertFalse(WhatsNewStore.section(of: bilingual, for: .en).contains("Linha em português"))
    }

    func testFallsBackWhenTheLanguageIsMissingOrThereAreNoMarkers() {
        let onlyEnglish = "<!-- en -->\n- Only English."
        XCTAssertTrue(WhatsNewStore.section(of: onlyEnglish, for: .pt).contains("Only English"))
        XCTAssertEqual(WhatsNewStore.section(of: "plain notes", for: .pt), "plain notes")
    }

    func testPortugueseBoilerplateIsDroppedToo() {
        let cleaned = WhatsNewStore.clean(WhatsNewStore.section(of: bilingual, for: .pt))
        XCTAssertTrue(cleaned.contains("Correções e melhorias"))
        XCTAssertFalse(cleaned.contains("Instalar"))
    }

    func testTheWindowShowsTheLanguageInForce() {
        let previous = Localization.current
        defer { Localization.current = previous }
        let store = makeStore()
        let release = ReleaseInfo(tag: "v1.0.2", version: AppVersion("1.0.2")!, notes: bilingual,
                                  pageURL: URL(string: "https://example.com")!, dmgURL: nil, sha256: nil)

        Localization.current = .pt
        store.remember(release)
        XCTAssertTrue(store.consume(currentVersion: "1.0.2")?.notes.contains("Linha em português") == true)

        Localization.current = .en
        store.remember(release)
        XCTAssertTrue(store.consume(currentVersion: "1.0.2")?.notes.contains("English line") == true)
    }
}
