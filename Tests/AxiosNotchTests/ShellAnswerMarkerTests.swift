import AppKit
import SwiftTerm
import XCTest
@testable import AxiosNotch

final class ShellAnswerMarkerTests: XCTestCase {
    private func terminal() -> Terminal {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let terminal = view.getTerminal()
        terminal.resize(cols: 80, rows: 24)
        return terminal
    }

    private func answer(_ terminal: Terminal, _ marker: ShellAnswerMarker) -> String {
        let text = String(data: terminal.getBufferAsData(), encoding: .utf8) ?? ""
        return AnswerExtractor.answer(in: text, since: marker.rowOffset(in: terminal), dropsPrompt: true)
    }

    func testShortAnswerAfterFullScrollback() {
        let terminal = terminal()
        terminal.feed(text: (0..<600).map { "old\($0)\r\n" }.joined() + "$ command")
        let marker = ShellAnswerMarker(terminal: terminal)
        terminal.feed(text: "\r\nfirst\r\nsecond\r\n$ ")
        XCTAssertEqual(answer(terminal, marker), "first\nsecond")
    }

    func testLongAnswerCopiesTheRetainedPart() {
        let terminal = terminal()
        terminal.feed(text: "$ command")
        let marker = ShellAnswerMarker(terminal: terminal)
        terminal.feed(text: "\r\n" + (0..<650).map { "result\($0)\r\n" }.joined() + "$ ")
        let copied = answer(terminal, marker)
        XCTAssertTrue(copied.hasSuffix("result649"))
        XCTAssertFalse(copied.contains("$ command"))
        XCTAssertFalse(copied.isEmpty)
    }

    func testClearAndHardResetDoNotReuseTheOldPosition() {
        for escape in ["\u{1b}[2J\u{1b}[H", "\u{1b}c"] {
            for history in ["", "old\r\nolder\r\n"] {
                let terminal = terminal()
                terminal.feed(text: history + "$ command")
                let marker = ShellAnswerMarker(terminal: terminal)
                terminal.feed(text: escape + "new result\r\n$ ")
                XCTAssertEqual(answer(terminal, marker), "new result")
            }
        }
    }

    func testResizeTracksThePromptAfterEarlierRowsReflow() {
        let terminal = terminal()
        terminal.feed(text: String(repeating: "x", count: 70) + "\r\n$ command")
        let marker = ShellAnswerMarker(terminal: terminal)
        terminal.resize(cols: 40, rows: 24)
        terminal.feed(text: "\r\nnew result\r\n$ ")
        XCTAssertEqual(answer(terminal, marker), "new result")
    }
}
