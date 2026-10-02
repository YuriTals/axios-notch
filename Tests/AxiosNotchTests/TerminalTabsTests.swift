import XCTest
@testable import AxiosNotch

/// These open real login shells (the clean-shell tool), so they exercise the
/// actual session bookkeeping, and close them again before finishing.
final class TerminalTabsTests: XCTestCase {
    private var store: TerminalSessionStore!

    override func setUp() { store = TerminalSessionStore() }
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

    func testClosingATabReallyEndsItsShell() throws {
        let key = store.ensureSelected(.shell)
        let started = expectation(description: "shell started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { started.fulfill() }
        wait(for: [started], timeout: 3)

        // The shell's pid is visible through its directory lookup; recover it
        // from the child list of this test process.
        let children = Process()
        children.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        children.arguments = ["-P", "\(getpid())"]
        let pipe = Pipe(); children.standardOutput = pipe
        try children.run(); children.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = output.split(separator: "\n").compactMap { pid_t($0) }.filter { $0 != children.processIdentifier }
        let pid = try XCTUnwrap(pids.first, "no shell child found")
        XCTAssertEqual(kill(pid, 0), 0)                            // alive

        store.close(key)

        let ended = expectation(description: "shell ended")
        DispatchQueue.global().async {
            for _ in 0..<40 where kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.1) }
            ended.fulfill()
        }
        wait(for: [ended], timeout: 6)
        // Reaped zombies report ESRCH; an unreaped one is still "alive" to kill(0)
        // but is no longer running, so also accept a non-running state.
        let status = Process()
        status.executableURL = URL(fileURLWithPath: "/bin/ps")
        status.arguments = ["-o", "state=", "-p", "\(pid)"]
        let out = Pipe(); status.standardOutput = out
        try status.run(); status.waitUntilExit()
        let state = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Give the shell a moment to start, then ask the OS where it is.
        let expectation = expectation(description: "shell started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 3)
        let actual = store.currentDirectory(for: key).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        XCTAssertEqual(actual, folder.resolvingSymlinksInPath().path)
        XCTAssertEqual(store.title(for: key), folder.lastPathComponent)
    }
}
