import SwiftTerm
import XCTest
@testable import AxiosNotch

enum ShellIntegrationSupport {
    static let prompt = "AXN_TEST_PROMPT> "

    static func store() -> TerminalSessionStore {
        TerminalSessionStore { view, tool, directory in
            // Same command the app would run, but through `zsh -f` instead of the
            // user's login shell, so no profile (Oh My Zsh, prompts, slow init) is read.
            var args = ["-f"]
            if tool != .shell {
                let launch = PTYSession.launchArguments(for: tool).args
                args += launch.drop { $0 == "-l" }
            }
            view.startProcess(executable: "/bin/zsh", args: args, environment: [
                "TERM=xterm-256color", "LANG=en_US.UTF-8",
                "HOME=\(NSHomeDirectory())", "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
                "PROMPT=\(prompt)", "RPROMPT=", "PROMPT_EOL_MARK="
            ], currentDirectory: directory)
        }
    }

    /// The screen text with wrapped rows glued back together, for "does it contain X".
    static func screen(of view: LocalProcessTerminalView) -> String {
        lines(in: view).joined()
    }

    static func lines(in view: LocalProcessTerminalView) -> [String] {
        let text = String(data: view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        return AnswerExtractor.lines(of: text)
    }

    static func waitForPrompt(in views: [LocalProcessTerminalView], timeout: TimeInterval = 4,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        try wait("shell prompt", timeout: timeout, file: file, line: line) {
            views.allSatisfy { $0.process?.running == true && lines(in: $0).last == prompt }
        }
    }

    static func wait(_ description: String, timeout: TimeInterval,
                     file: StaticString = #filePath, line: UInt = #line,
                     until condition: @escaping () -> Bool) throws {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        ready.expectationDescription = description
        guard XCTWaiter.wait(for: [ready], timeout: timeout) == .completed else {
            XCTFail("Timed out waiting for \(description)", file: file, line: line)
            throw NSError(domain: "ShellIntegrationSupport", code: 1)
        }
    }
}
