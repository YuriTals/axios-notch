import XCTest
@testable import AxiosNotch

final class ApprovalDetectorTests: XCTestCase {
    func testClaudeCommandPrompt() {
        let screen = """
        ╭──────────────────────────────────────────╮
        │ Bash command                             │
        │   swift test                             │
        │ Do you want to proceed?                  │
        │ ❯ 1. Yes                                 │
        │   2. Yes, and don't ask again for swift  │
        │   3. No, and tell Claude what to do differently (esc) │
        ╰──────────────────────────────────────────╯
        """
        XCTAssertTrue(ApprovalDetector.needsApproval(text: screen))
    }

    func testClaudeEditPrompt() {
        XCTAssertTrue(ApprovalDetector.needsApproval(text: """
         Do you want to make this edit to main.swift?
         ❯ 1. Yes
           2. Yes, allow all edits during this session (shift+tab)
           3. No, and tell Claude what to do differently (esc)
        """))
    }

    func testCodexPrompt() {
        XCTAssertTrue(ApprovalDetector.needsApproval(text: """
          Would you like to run the following command?
          $ rm -rf build
          › 1. Yes, proceed (y)
            2. Yes, and don't ask again for commands that start with `rm` (p)
            3. No, and tell Codex what to do differently (esc)
        """))
    }

    func testClaudeMultipleChoiceQuestion() {
        // The exact screen Claude Code showed for an AskUserQuestion prompt.
        XCTAssertTrue(ApprovalDetector.needsApproval(text: """
         ☐ Teste notch

        O Axios Notch te notificou sobre esta pergunta?

        ❯ 1. Sim, notificou
             O notch apareceu ou reagiu quando a pergunta chegou.
          2. Não notificou
             Nada aconteceu no notch, só vi a pergunta no terminal.
          3. Notificou com atraso
          4. Type something.
        ────────────────────────────────────────
          5. Chat about this

        Enter to select · ↑/↓ to navigate · Esc to cancel
        """))
    }

    func testClaudePlanApprovalAndAnswerReview() {
        XCTAssertTrue(ApprovalDetector.needsApproval(text: """
         Ready to code?
         ❯ 1. Yes, auto-accept edits
           2. Yes, manually approve edits
           3. No, keep planning
        """))
        XCTAssertTrue(ApprovalDetector.needsApproval(text: "Ready to submit your answers?\n ❯ 1. Submit answers\n   2. Cancel"))
    }

    func testCodexQuestion() {
        XCTAssertTrue(ApprovalDetector.needsApproval(text: "tab to add notes · enter to submit answer · ←/→ to navigate questions · esc to interrupt"))
    }

    func testOtherMenusAndChatAreNotWaiting() {
        // A picker the user opened themselves closes with "Esc to close", not "cancel".
        XCTAssertFalse(ApprovalDetector.needsApproval(text: "↑/↓ to navigate · Enter to select · Esc to close"))
        XCTAssertFalse(ApprovalDetector.needsApproval(text: "I'm ready to code? Let me know when to start."))
        XCTAssertFalse(ApprovalDetector.needsApproval(text: "Press Enter to select the next file"))
    }

    func testOrdinaryScreensAreNotApprovals() {
        XCTAssertFalse(ApprovalDetector.needsApproval(text: "❯ write me a poem\n✻ Thinking…  (esc to interrupt)"))
        XCTAssertFalse(ApprovalDetector.needsApproval(text: "Do you want to proceed with the refactor? I can start now."))
        XCTAssertFalse(ApprovalDetector.needsApproval(lines: []))
        XCTAssertFalse(ApprovalDetector.needsApproval(text: ""))
    }

    func testApprovalPhrasesExistInBothLanguagesAndFit() {
        for lang in [Lang.pt, .en] {
            XCTAssertGreaterThanOrEqual(PhraseBook.approval(lang).count, 3)
            for line in PhraseBook.approval(lang) { XCTAssertLessThanOrEqual(line.count, 32, line) }
        }
        for previous in PhraseBook.approval(.pt) {
            for index in 0..<2 {
                XCTAssertNotEqual(PhraseBook.pickApproval(avoiding: previous, language: .pt, randomIndex: { _ in index }), previous)
            }
        }
    }
}
