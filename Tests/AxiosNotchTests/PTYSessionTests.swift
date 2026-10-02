import XCTest
@testable import AxiosNotch

final class PTYSessionTests: XCTestCase {
    func testCleanShellIsJustAnInteractiveLoginShell() {
        let launch = PTYSession.launchArguments(for: nil)
        XCTAssertEqual(launch.args, ["-l"])
        XCTAssertFalse(launch.executable.isEmpty)
    }

    func testProviderRunsItsCLIThroughTheLoginShell() {
        let claude = PTYSession.launchArguments(for: .claude)
        XCTAssertEqual(claude.args, ["-l", "-c", "claude"])

        let codex = PTYSession.launchArguments(for: .codex)
        XCTAssertEqual(codex.args, ["-l", "-c", "codex"])
        XCTAssertEqual(claude.executable, codex.executable)
    }

    func testSessionKeysAreStableAndDistinct() {
        XCTAssertEqual(TerminalSessionStore.key(for: nil), "shell")
        XCTAssertEqual(TerminalSessionStore.key(for: .claude), "claude")
        XCTAssertNotEqual(TerminalSessionStore.key(for: .claude), TerminalSessionStore.key(for: .codex))
    }

    func testUsageFormatting() {
        XCTAssertEqual(UsageFormat.tokens(950), "950")
        XCTAssertEqual(UsageFormat.tokens(12_340), "12.3k")
        XCTAssertEqual(UsageFormat.tokens(3_400_000), "3.4M")
        XCTAssertEqual(UsageFormat.tokens(142_000_000), "142M")
        XCTAssertEqual(UsageFormat.cost(1.5), "$1.50")

        let now = Date()
        XCTAssertEqual(UsageFormat.remaining(until: now.addingTimeInterval(4 * 3600 + 35 * 60 + 5), now: now), "reinicia em 4h 35min")
        XCTAssertEqual(UsageFormat.remaining(until: now.addingTimeInterval(12 * 60 + 5), now: now), "reinicia em 12min")
    }
}
