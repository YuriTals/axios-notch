import XCTest
@testable import AxiosNotch

final class AgentDirectoriesTests: XCTestCase {
    func testCustomDirectoriesOverrideHomeIndependently() {
        let environment = ["CODEX_HOME": "/tmp/custom codex", "CLAUDE_CONFIG_DIR": "/tmp/custom claude"]
        let home = URL(fileURLWithPath: "/tmp/default-home")
        XCTAssertEqual(AgentDirectories.configuration(for: .codex, environment: environment, home: home).path,
                       "/tmp/custom codex")
        XCTAssertEqual(AgentDirectories.configuration(for: .claude, environment: environment, home: home).path,
                       "/tmp/custom claude")
    }

    func testMissingAndEmptyVariablesFallBackToHome() {
        let home = URL(fileURLWithPath: "/tmp/default-home")
        for environment in [[:], ["CODEX_HOME": "", "CLAUDE_CONFIG_DIR": ""]] {
            XCTAssertEqual(AgentDirectories.configuration(for: .codex, environment: environment, home: home).path,
                           "/tmp/default-home/.codex")
            XCTAssertEqual(AgentDirectories.configuration(for: .claude, environment: environment, home: home).path,
                           "/tmp/default-home/.claude")
        }
    }
}
