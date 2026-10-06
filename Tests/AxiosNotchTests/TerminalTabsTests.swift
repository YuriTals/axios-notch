import XCTest
@testable import AxiosNotch

/// These open real shells (`zsh -f`, independent of the user's profile), so they exercise the
/// actual session bookkeeping, and close them again before finishing.
final class TerminalTabsTests: XCTestCase {
    private var store: TerminalSessionStore!

    override func setUp() { store = ShellIntegrationSupport.store() }
    override func tearDown() {
        for key in store.keys { store.close(key) }
        store = nil
    }

    func testFirstUseCreatesAndSelectsTabOne() {
        XCTAssertNil(store.selectedKey(for: .shell))
        let key = store.ensureSelected(.shell)
        XCTAssertEqual(key, SessionKey(provider: nil, number: 1))
        XCTAssertEqual(store.selectedKey(for: .shell), key)
        XCTAssertTrue(store.isActive(.shell))
        // Asking again must not open a second one.
        XCTAssertEqual(store.ensureSelected(.shell), key)
        XCTAssertEqual(store.keys(for: .shell).count, 1)
    }

    func testNewSessionsAreNumberedAndSelected() {
        store.ensureSelected(.shell)
        let second = store.openSession(.shell, directory: nil)
        let third = store.openSession(.shell, directory: NSTemporaryDirectory())
        XCTAssertEqual([second.number, third.number], [2, 3])
        XCTAssertEqual(store.selectedKey(for: .shell), third)
        XCTAssertEqual(store.keys(for: .shell).map(\.number), [1, 2, 3])
    }

    func testTabsAreCappedPerTool() {
        for _ in 0..<(SessionKey.maxPerProvider + 3) { store.openSession(.shell, directory: nil) }
        XCTAssertEqual(store.keys(for: .shell).count, SessionKey.maxPerProvider)
    }

    func testSelectingAndClosingMovesToANeighbour() {
        let one = store.ensureSelected(.shell)
        let two = store.openSession(.shell, directory: nil)
        let three = store.openSession(.shell, directory: nil)

        store.select(id: one.id)
        XCTAssertEqual(store.selectedKey(for: .shell), one)

        store.select(two)
        store.close(two)                                          // the middle one
        XCTAssertEqual(store.keys(for: .shell), [one, three])
        XCTAssertEqual(store.selectedKey(for: .shell), three)        // its neighbour took over

        store.close(three)
        XCTAssertEqual(store.selectedKey(for: .shell), one)
        store.close(one)
        XCTAssertNil(store.selectedKey(for: .shell))                 // nothing left: the panel closes
        XCTAssertFalse(store.isActive(.shell))
    }

    func testClosingATabThatIsNotSelectedKeepsTheSelection() {
        let one = store.ensureSelected(.shell)
        let two = store.openSession(.shell, directory: nil)
        store.close(one)
        XCTAssertEqual(store.selectedKey(for: .shell), two)
    }

    /// Direct children of this test process (other tests may leave shells of their own behind).
    private func childPIDs() throws -> Set<pid_t> {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", "\(getpid())"]
        let pipe = Pipe(); pgrep.standardOutput = pipe
        try pgrep.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return Set(output.split(separator: "\n").compactMap { pid_t($0) }).subtracting([pgrep.processIdentifier])
    }

    /// `ps` state letter, or empty when the process is gone. A zombie ("Z") is dead but not yet reaped.
    private func processState(_ pid: pid_t) throws -> String {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "state=", "-p", "\(pid)"]
        let pipe = Pipe(); ps.standardOutput = pipe
        try ps.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testClosingATabReallyEndsItsShell() throws {
        let before = try childPIDs()
        let key = store.ensureSelected(.shell)

        // The tab's shell is the child that appeared because of this tab, not just the first one listed.
        var pid: pid_t = 0
        let deadline = Date().addingTimeInterval(5)
        while pid == 0, Date() < deadline {
            pid = try childPIDs().subtracting(before).first ?? 0
            if pid == 0 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        }
        XCTAssertNotEqual(pid, 0, "no new shell child found")
        guard pid != 0 else { return }
        XCTAssertEqual(kill(pid, 0), 0)                            // alive

        store.close(key)

        // Gone (ESRCH) or dead-but-unreaped (zombie): either way no longer running.
        var state = try processState(pid)
        let endBy = Date().addingTimeInterval(8)
        while !(state.isEmpty || state.hasPrefix("Z")), Date() < endBy {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            state = try processState(pid)
        }
        XCTAssertTrue(state.isEmpty || state.hasPrefix("Z"), "shell still running, state: \(state)")
    }

    func testClosingAnUnknownKeyIsHarmless() {
        store.close(SessionKey(provider: .codex, number: 9))
        store.select(SessionKey(provider: .codex, number: 9))
        XCTAssertNil(store.selectedKey(for: .agent(.codex)))
        XCTAssertEqual(store.unreadCount(.agent(.codex)), 0)
    }

    func testNewTabStartsInTheRequestedFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("axios-tab-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let key = store.openSession(.shell, directory: folder.path)
        // Wait until the shell is ready, then ask the OS where it is.
        try ShellIntegrationSupport.waitForPrompt(in: [try XCTUnwrap(store.view(for: key))])
        let actual = store.currentDirectory(for: key).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        XCTAssertEqual(actual, folder.resolvingSymlinksInPath().path)
        XCTAssertEqual(store.title(for: key), folder.lastPathComponent)
    }
}
