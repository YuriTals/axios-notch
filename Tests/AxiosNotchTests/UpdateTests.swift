import XCTest
@testable import AxiosNotch

final class AppVersionTests: XCTestCase {
    func testOrdersNumericallyNotAsText() {
        XCTAssertTrue(AppVersion("1.0.2")! > AppVersion("1.0.1")!)
        XCTAssertTrue(AppVersion("1.10.0")! > AppVersion("1.9.9")!)
        XCTAssertTrue(AppVersion("2.0")! > AppVersion("1.99.99")!)
    }

    func testIgnoresLeadingVAndSuffixAndMissingParts() {
        XCTAssertEqual(AppVersion("v1.0.1"), AppVersion("1.0.1"))
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertEqual(AppVersion("1.2.0-beta.1"), AppVersion("1.2.0"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1.x.2"))
    }
}

final class ReleaseParserTests: XCTestCase {
    private let digest = String(repeating: "ab", count: 32)

    private func json(tag: String = "v1.0.2", draft: Bool = false, prerelease: Bool = false,
                      body: String? = nil, assets: String? = nil) -> Data {
        let body = body ?? "Notes\\n\\nSHA-256 of the `.dmg`: `\(digest)`"
        let assets = assets ?? #"[{"name":"AxiosNotch-1.0.2.dmg","browser_download_url":"https://github.com/o/r/releases/download/v1.0.2/AxiosNotch-1.0.2.dmg"}]"#
        return Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"html_url":"https://github.com/o/r/releases/tag/\#(tag)","body":"\#(body)","assets":\#(assets)}"#.utf8)
    }

    func testParsesVersionDownloadAndHash() throws {
        let release = try XCTUnwrap(ReleaseParser.parse(json()))
        XCTAssertEqual(release.version, AppVersion("1.0.2"))
        XCTAssertEqual(release.dmgURL?.lastPathComponent, "AxiosNotch-1.0.2.dmg")
        XCTAssertEqual(release.sha256, digest)
    }

    func testHashIsOptionalButThenNothingInstallsItself() throws {
        let release = try XCTUnwrap(ReleaseParser.parse(json(body: "No hash here")))
        XCTAssertNil(release.sha256)
    }

    func testIgnoresLongerHexRunsAndUppercase() {
        XCTAssertNil(ReleaseParser.sha256(in: String(repeating: "a", count: 65)))
        XCTAssertEqual(ReleaseParser.sha256(in: "x " + String(repeating: "AB", count: 32)), digest)
    }

    func testIgnoresDraftsPrereleasesAndBrokenJSON() {
        XCTAssertNil(ReleaseParser.parse(json(draft: true)))
        XCTAssertNil(ReleaseParser.parse(json(prerelease: true)))
        XCTAssertNil(ReleaseParser.parse(Data("not json".utf8)))
        XCTAssertNil(ReleaseParser.parse(json(tag: "latest")))
    }

    func testReleaseWithoutDMGHasNoDownload() throws {
        let release = try XCTUnwrap(ReleaseParser.parse(json(assets: #"[{"name":"source.zip","browser_download_url":"https://x/y.zip"}]"#)))
        XCTAssertNil(release.dmgURL)
    }
}

final class UpdateInstallerTests: XCTestCase {
    private func makeTemp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("axios-update-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testSHA256OfAFileMatchesTheKnownDigest() throws {
        let file = try makeTemp().appendingPathComponent("a.bin")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try UpdateInstaller.sha256(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    /// Runs the real script with a dead pid and folders whose names need quoting.
    private func runSwap(appExists: Bool, stagedExists: Bool = true) throws -> (dir: URL, app: URL, staged: URL, backup: URL) {
        let dir = try makeTemp()
        let app = dir.appendingPathComponent("My App's.app")
        let staged = dir.appendingPathComponent(".My App's.update.app")
        let backup = dir.appendingPathComponent(".My App's.old.app")
        if appExists { try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true); try Data("old".utf8).write(to: app.appendingPathComponent("v")) }
        if stagedExists { try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true); try Data("new".utf8).write(to: staged.appendingPathComponent("v")) }
        let dead = Process(); dead.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try dead.run(); dead.waitUntilExit()
        let script = dir.appendingPathComponent("swap.sh")
        try UpdateInstaller.swapScript(pid: dead.processIdentifier, app: app.path, staged: staged.path, backup: backup.path, relaunch: false)
            .write(to: script, atomically: true, encoding: .utf8)
        let sh = Process(); sh.executableURL = URL(fileURLWithPath: "/bin/sh"); sh.arguments = [script.path]
        try sh.run(); sh.waitUntilExit()
        return (dir, app, staged, backup)
    }

    private func release(dmg: URL?, sha: String?) -> ReleaseInfo {
        ReleaseInfo(tag: "v9.9.9", version: AppVersion("9.9.9")!, notes: "", pageURL: URL(string: "https://example.com")!, dmgURL: dmg, sha256: sha)
    }

    private func assertPrepareFails(_ release: ReleaseInfo, app: URL, _ expected: String, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await UpdateInstaller.prepare(release, appURL: app)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertTrue("\(error)".contains(expected), "got \(error)", file: file, line: line)
        }
    }

    func testPrepareRefusesAnythingThatCannotBeVerified() async throws {
        let dir = try makeTemp()
        let app = dir.appendingPathComponent("Fake.app")
        let file = dir.appendingPathComponent("fake.dmg")
        try Data("not a real dmg".utf8).write(to: file)
        let wrongHash = String(repeating: "0", count: 64)

        await assertPrepareFails(release(dmg: nil, sha: wrongHash), app: app, "noDMG")
        await assertPrepareFails(release(dmg: file, sha: nil), app: app, "missingHash")
        await assertPrepareFails(release(dmg: file, sha: wrongHash), app: app, "hashMismatch")
        await assertPrepareFails(release(dmg: file, sha: wrongHash), app: dir.appendingPathComponent("tool"), "notInstalledApp")
    }

    func testPrepareStopsAtAnImageThatIsNotADiskImage() async throws {
        let dir = try makeTemp()
        let file = dir.appendingPathComponent("fake.dmg")
        try Data("not a real dmg".utf8).write(to: file)
        let good = try UpdateInstaller.sha256(of: file)
        // The hash matches, so only mounting can stop it.
        await assertPrepareFails(release(dmg: file, sha: good), app: dir.appendingPathComponent("Fake.app"), "mountFailed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".Fake.update.app").path))
    }

    func testSwapReplacesTheAppAndLeavesNoLeftovers() throws {
        let r = try runSwap(appExists: true)
        XCTAssertEqual(try String(contentsOf: r.app.appendingPathComponent("v")), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.staged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.backup.path))
    }

    func testSwapDoesNotTouchTheAppWhenNothingIsStaged() throws {
        let r = try runSwap(appExists: true, stagedExists: false)
        XCTAssertEqual(try String(contentsOf: r.app.appendingPathComponent("v")), "old")
    }
}

@MainActor
final class UpdateStoreTests: XCTestCase {
    private func store(current: String, body: String, auto: Bool = true, calls: Counter = Counter()) -> UpdateStore {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)")!
        defaults.set(auto, forKey: "autoCheckUpdates")
        return UpdateStore(defaults: defaults, currentVersion: current) {
            calls.count += 1
            return Data(body.utf8)
        }
    }

    final class Counter { var count = 0 }

    private let newer = #"{"tag_name":"v1.0.2","html_url":"https://github.com/o/r/releases/tag/v1.0.2","body":"","assets":[]}"#

    func testReportsANewerRelease() async {
        let s = store(current: "1.0.1", body: newer)
        await s.check()
        XCTAssertEqual(s.availableRelease?.version, AppVersion("1.0.2"))
        XCTAssertNotNil(s.lastCheck)
    }

    func testSameOrOlderReleaseMeansUpToDate() async {
        let s = store(current: "1.0.2", body: newer)
        await s.check()
        XCTAssertEqual(s.state, .upToDate)
        let t = store(current: "2.0.0", body: newer)
        await t.check()
        XCTAssertEqual(t.state, .upToDate)
    }

    func testBadResponseIsAFailureNotACrash() async {
        let s = store(current: "1.0.1", body: "oops")
        await s.check()
        if case .failed = s.state {} else { XCTFail("expected a failure, got \(s.state)") }
    }

    func testAutomaticCheckHonoursTheSwitchAndTheInterval() async throws {
        let calls = Counter()
        let off = store(current: "1.0.1", body: newer, auto: false, calls: calls)
        off.checkIfDue()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(calls.count, 0)

        let on = store(current: "1.0.1", body: newer, auto: true, calls: calls)
        on.checkIfDue()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls.count, 1)
    }

    func testInstallNeedsAnAvailableRelease() async {
        let s = store(current: "1.0.1", body: newer)
        await s.install()   // nothing available yet: must do nothing
        XCTAssertEqual(s.state, .idle)
    }
}
