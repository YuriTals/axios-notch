import XCTest
@testable import AxiosNotch

final class SavedTabsTests: XCTestCase {
    func testRoundTripsThroughUserDefaults() {
        let suite = "axios-tabs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(SavedTabs.load(defaults: defaults), SavedTabs())               // nothing yet
        let saved = SavedTabs(tabs: [
            SavedTab(provider: "claude", directory: "/Users/dev/code/a", wasSelected: true),
            SavedTab(provider: nil, directory: nil, wasSelected: false),
        ])
        saved.save(defaults: defaults)
        XCTAssertEqual(SavedTabs.load(defaults: defaults), saved)
    }

    func testCorruptDataIsIgnoredInsteadOfBreakingLaunch() {
        let suite = "axios-tabs-bad-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "savedTabs")
        XCTAssertTrue(SavedTabs.load(defaults: defaults).tabs.isEmpty)
    }

    func testMissingFoldersFallBackToHomeAndUnknownToolsAreSkipped() {
        let saved = SavedTabs(tabs: [
            SavedTab(provider: "claude", directory: "/gone", wasSelected: false),
            SavedTab(provider: "codex", directory: "/here", wasSelected: true),
            SavedTab(provider: "wat", directory: "/here", wasSelected: false),            // a tool this version doesn't know
            SavedTab(provider: nil, directory: nil, wasSelected: false),
        ])
        let tabs = saved.restorable(folderExists: { $0 == "/here" })
        XCTAssertEqual(tabs.map(\.provider), ["claude", "codex", nil])
        XCTAssertNil(tabs[0].directory)                                                   // /gone → home
        XCTAssertEqual(tabs[1].directory, "/here")
    }

    func testNoMoreThanTheLimitPerTool() {
        let many = SavedTabs(tabs: (0..<10).map { _ in SavedTab(provider: "claude", directory: nil, wasSelected: false) }
                                  + (0..<2).map { _ in SavedTab(provider: nil, directory: nil, wasSelected: false) })
        let tabs = many.restorable(perTool: 3, folderExists: { _ in true })
        XCTAssertEqual(tabs.filter { $0.provider == "claude" }.count, 3)
        XCTAssertEqual(tabs.filter { $0.provider == nil }.count, 2)
    }

    /// Real shells: open tabs in two folders, snapshot, then restore into a brand-new store.
    func testReopensTheSameTabsInTheSameFolders() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("axios-restore-\(UUID().uuidString)")
        let one = base.appendingPathComponent("um"), two = base.appendingPathComponent("dois")
        try FileManager.default.createDirectory(at: one, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let first = ShellIntegrationSupport.store()
        defer { for key in first.keys { first.close(key) } }
        let a = first.openSession(.shell, directory: one.path)
        let b = first.openSession(.shell, directory: two.path)
        first.select(a)                                                                   // the *first* tab is the selected one
        try ShellIntegrationSupport.waitForPrompt(in: [
            try XCTUnwrap(first.view(for: a)), try XCTUnwrap(first.view(for: b))
        ])
        let saved = first.snapshot()
        for key in first.keys { first.close(key) }
        XCTAssertEqual(saved.tabs.count, 2)
        XCTAssertEqual(saved.tabs.map(\.wasSelected), [true, false])
        let second = ShellIntegrationSupport.store()
        defer { for key in second.keys { second.close(key) } }
        XCTAssertEqual(second.restoreTabs(saved), 2)
        XCTAssertEqual(second.keys.count, 2)
        XCTAssertEqual(second.selectedKey(for: .shell)?.number, 1)                           // selection restored
        let restoredViews = try second.keys.map { try XCTUnwrap(second.view(for: $0)) }
        try ShellIntegrationSupport.waitForPrompt(in: restoredViews)
        let folders = second.keys.compactMap { second.currentDirectory(for: $0) }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        XCTAssertEqual(folders, [one, two].map { $0.resolvingSymlinksInPath().path })

        XCTAssertEqual(second.restoreTabs(saved), 0, "must not duplicate tabs when some are already open")
    }

    func testTheSettingDefaultsOnAndPersists() {
        let suite = "axios-reopen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.reopenTabs)
        first.reopenTabs = false
        XCTAssertFalse(AppSettings(defaults: defaults).reopenTabs)
    }
}
