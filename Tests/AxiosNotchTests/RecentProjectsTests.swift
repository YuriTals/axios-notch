import XCTest
@testable import AxiosNotch

final class RecentProjectsTests: XCTestCase {
    private let home = "/Users/yuri"

    func testMostRecentFirstWithoutDuplicates() {
        var recents = RecentProjects()
        recents.record("/Users/yuri/code/a", home: home)
        recents.record("/Users/yuri/code/b", home: home)
        recents.record("/Users/yuri/code/a/", home: home)           // same folder, trailing slash
        XCTAssertEqual(recents.paths, ["/Users/yuri/code/a", "/Users/yuri/code/b"])
    }

    func testHomeRootAndEmptyAreNotProjects() {
        var recents = RecentProjects()
        for path in ["/Users/yuri", "/Users/yuri/", "/", ""] { recents.record(path, home: home) }
        XCTAssertTrue(recents.paths.isEmpty)
    }

    func testKeepsOnlyTheMostRecentEight() {
        var recents = RecentProjects()
        for index in 1...12 { recents.record("/Users/yuri/p\(index)", home: home) }
        XCTAssertEqual(recents.paths.count, RecentProjects.limit)
        XCTAssertEqual(recents.paths.first, "/Users/yuri/p12")
        XCTAssertEqual(recents.paths.last, "/Users/yuri/p5")
    }

    func testSuggestionsSkipMissingFoldersAndTheCurrentOne() {
        var recents = RecentProjects()
        for name in ["gone", "here", "current", "other"] { recents.record("/Users/yuri/\(name)", home: home) }
        let shown = recents.suggestions(excluding: ["/Users/yuri/current"], max: 5, exists: { !$0.hasSuffix("gone") })
        XCTAssertEqual(shown, ["/Users/yuri/other", "/Users/yuri/here"])
        XCTAssertEqual(recents.suggestions(max: 1, exists: { _ in true }).count, 1)
    }

    func testPersistsAcrossLaunches() {
        let suite = "axios-recents-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var recents = RecentProjects.load(defaults: defaults)
        recents.record("/Users/yuri/x", home: home)
        recents.save(defaults: defaults)
        XCTAssertEqual(RecentProjects.load(defaults: defaults).paths, ["/Users/yuri/x"])
        recents.clear()
        recents.save(defaults: defaults)
        XCTAssertTrue(RecentProjects.load(defaults: defaults).paths.isEmpty)
    }
}
