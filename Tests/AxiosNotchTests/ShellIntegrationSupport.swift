import SwiftTerm
import XCTest
@testable import AxiosNotch

enum ShellIntegrationSupport {
    static let prompt = "AXN_TEST_PROMPT> "

    static func store() -> TerminalSessionStore {
        TerminalSessionStore { view, tool, directory in
            precondition(tool == .shell)
            view.startProcess(executable: "/bin/zsh", args: ["-f"], environment: [
                "TERM=xterm-256color", "LANG=en_US.UTF-8",
                "HOME=\(NSHomeDirectory())", "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
                "PROMPT=\(prompt)", "RPROMPT=", "PROMPT_EOL_MARK="
            ], currentDirectory: directory)
        }
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
