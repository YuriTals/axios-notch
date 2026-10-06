import XCTest
@testable import AxiosNotch

final class RecentProjectsTests: XCTestCase {
    private let home = "/Users/dev"

    func testMostRecentFirstWithoutDuplicates() {
        var recents = RecentProjects()
        recents.record("/Users/dev/code/a", home: home)
        recents.record("/Users/dev/code/b", home: home)
        recents.record("/Users/dev/code/a/", home: home)           // same folder, trailing slash
        XCTAssertEqual(recents.paths, ["/Users/dev/code/a", "/Users/dev/code/b"])
    }

    func testHomeRootAndEmptyAreNotProjects() {
        var recents = RecentProjects()
        for path in ["/Users/dev", "/Users/dev/", "/", ""] { recents.record(path, home: home) }
        XCTAssertTrue(recents.paths.isEmpty)
    }

    func testKeepsOnlyTheMostRecentEight() {
        var recents = RecentProjects()
        for index in 1...12 { recents.record("/Users/dev/p\(index)", home: home) }
        XCTAssertEqual(recents.paths.count, RecentProjects.limit)
        XCTAssertEqual(recents.paths.first, "/Users/dev/p12")
        XCTAssertEqual(recents.paths.last, "/Users/dev/p5")
    }

    func testSuggestionsSkipMissingFoldersAndTheCurrentOne() {
        var recents = RecentProjects()
        for name in ["gone", "here", "current", "other"] { recents.record("/Users/dev/\(name)", home: home) }
        let shown = recents.suggestions(excluding: ["/Users/dev/current"], max: 5, exists: { !$0.hasSuffix("gone") })
        XCTAssertEqual(shown, ["/Users/dev/other", "/Users/dev/here"])
        XCTAssertEqual(recents.suggestions(max: 1, exists: { _ in true }).count, 1)
    }

    func testPersistsAcrossLaunches() {
        let suite = "axios-recents-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var recents = RecentProjects.load(defaults: defaults)
        recents.record("/Users/dev/x", home: home)
        recents.save(defaults: defaults)
        XCTAssertEqual(RecentProjects.load(defaults: defaults).paths, ["/Users/dev/x"])
        recents.clear()
        recents.save(defaults: defaults)
        XCTAssertTrue(RecentProjects.load(defaults: defaults).paths.isEmpty)
    }
}
