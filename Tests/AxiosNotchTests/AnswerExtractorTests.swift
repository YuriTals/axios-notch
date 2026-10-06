import XCTest
import AppKit
@testable import AxiosNotch

final class AnswerExtractorTests: XCTestCase {
    func testLinesDropTheEmptyTailOfTheScreen() {
        XCTAssertEqual(AnswerExtractor.lines(of: "a\nb\n\n   \n\n"), ["a", "b"])
        XCTAssertEqual(AnswerExtractor.lineCount(of: ""), 0)
        XCTAssertEqual(AnswerExtractor.lineCount(of: "x\r\ny\r\n"), 2)
    }

    func testShellAnswerIsTheOutputWithoutTheNextPrompt() {
        let before = "~ ❯ echo hi"                                   // marker taken at Enter
        let marker = AnswerExtractor.lineCount(of: before)
        let after = "~ ❯ echo hi\nhi\nthere\n~ ❯ \n\n\n"
        XCTAssertEqual(AnswerExtractor.answer(in: after, since: marker, dropsPrompt: true), "hi\nthere")
        // Without a prompt to drop (a CLI), every line stays.
        XCTAssertEqual(AnswerExtractor.answer(in: "q\nhi\nthere", since: 1, dropsPrompt: false), "hi\nthere")
    }

    func testBoxDrawingAndTrailingSpacesAreCleanedButTextIsKept() {
        let screen = "❯ explain\nHere is the reply   \n  with two lines\n╭────────────╮\n│ > next     │\n╰────────────╯\n──────"
        let answer = AnswerExtractor.answer(in: screen, since: 1, dropsPrompt: false)
        XCTAssertEqual(answer, "Here is the reply\n  with two lines\n│ > next     │")   // a box row with text stays; pure frames go
    }

    func testNothingAfterTheMarkerIsAnEmptyAnswer() {
        XCTAssertEqual(AnswerExtractor.answer(in: "a\nb", since: 2, dropsPrompt: false), "")
        XCTAssertEqual(AnswerExtractor.answer(in: "a\nb", since: 99, dropsPrompt: true), "")
        XCTAssertEqual(AnswerExtractor.answer(in: "", since: 0, dropsPrompt: true), "")
    }

    /// End to end with a real shell: type a command, wait, and read back its output.
    func testCopiesTheRealOutputOfACommandInARealShell() throws {
        let store = ShellIntegrationSupport.store()
        defer { for key in store.keys { store.close(key) } }
        let key = store.ensureSelected(.shell)
        let view = try XCTUnwrap(store.view(for: key))
        XCTAssertNil(store.lastAnswer(for: key))                          // nothing submitted yet

        try ShellIntegrationSupport.waitForPrompt(in: [view])

        view.send(txt: "echo AXN_UNIQUE_ONE; echo AXN_UNIQUE_TWO\r")
        try ShellIntegrationSupport.wait("command output and next prompt", timeout: 5) {
            Array(ShellIntegrationSupport.lines(in: view).suffix(3)) == [
                "AXN_UNIQUE_ONE", "AXN_UNIQUE_TWO", ShellIntegrationSupport.prompt
            ]
        }

        let answer = try XCTUnwrap(store.lastAnswer(for: key), "no answer captured")
        XCTAssertEqual(answer, "AXN_UNIQUE_ONE\nAXN_UNIQUE_TWO")
        XCTAssertFalse(answer.contains("echo AXN_UNIQUE"), "the typed command must not be part of the answer: \(answer)")
        XCTAssertTrue(store.hasAnswer(for: key))
    }
}

final class CLIAnswerTests: XCTestCase {
    /// The screen Claude Code actually showed (from the user's screenshot).
    private let claudeScreen = """
     ▐▛███▜▌   Claude Code v2.1.287
    ▝▜█████▛▘  Sonnet 5.5 · Claude Pro
      ▘▘ ▝▝    /Users/dev

    ▌ Using Sonnet 5.5 (from .claude/settings.json) · /model

    ❯ teste

    ● Olá! Recebi o "teste" e está tudo funcionando. Como posso ajudar?

    ✻ Baked for 1s · done 2:39 PM





    ────────────────────────────────────────────────────────────
    ❯
    ────────────────────────────────────────────────────────────
      ▸▸ auto mode on (shift+tab to cycle) · ← for agents
    """

    func testExtractsTheReplyAboveTheInputBox() {
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: claudeScreen), "Olá! Recebi o \"teste\" e está tudo funcionando. Como posso ajudar?")
    }

    func testMultiLineReplyWithCodeKeepsItsShape() {
        let screen = """
        ❯ show me code

        ● Here it is:

          let x = 1
          print(x)

        ✻ Worked for 3s
        ────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────
        """
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen), "Here it is:\n\n  let x = 1\n  print(x)")
    }

    func testTextTypedInTheBoxIsNotTheAnswer() {
        // The user is half-way through typing the next message: the answer is still the previous one.
        let screen = claudeScreen.replacingOccurrences(of: "────────────────────────────────────────────────────────────\n❯\n", with: "────────────────────────────────────────────────────────────\n❯ and also this\n")
        XCTAssertTrue(AnswerExtractor.cliAnswer(in: screen).hasPrefix("Olá!"))
    }

    func testPicksTheLatestOfSeveralExchanges() {
        let screen = """
        ❯ first
        ● one
        ❯ second
        ● two
        ────────────────────────────────────────────────────────────
        ❯
        """
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen), "two")
    }

    func testCodexPromptGlyphWorksToo() {
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: "› hello\n\nHi there!\n────────────────────────────────────────────────────────────\n› Ask Codex"), "Hi there!")
    }

    func testNothingYetMeansEmpty() {
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: ""), "")
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: "Claude Code v2\n────────────────────────────────────────────────────────────\n❯\n────────────────────────────────────────────────────────────"), "")
    }
}

final class RealClaudeBulletTests: XCTestCase {
    /// What the real Claude Code left in the buffer: the ⏺ bullet followed by an
    /// empty-cell NUL, found by copying a live answer.
    func testTheRealBulletAndNulAreStripped() {
        let screen = "❯ responda apenas com a palavra: azul\n\n\u{23FA}\u{0} azul\n\n✻ Crunched for 1s · done 2:43 PM\n\n\n────────────────────────────────────────────────────────────\n❯ \u{0}\n────────────────────────────────────────────────────────────\n"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen), "azul")
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen.replacingOccurrences(of: "\u{23FA}\u{0} ", with: "\u{23FA} ")), "azul")
        // …and with no space at all after the bullet, which is what the live buffer gives once NULs are gone.
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen.replacingOccurrences(of: "\u{23FA}\u{0} ", with: "\u{23FA}")), "azul")
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: "❯ q\n\u{23FA}\u{0}verde\n────────────────────────────────────────────────────────────\n❯"), "verde")
    }

    func testCodexBulletIsStripped() {
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: "› oi\n\n• Olá! Tudo bem?\n────────────────────────────────────────────────────────────\n› Ask"), "Olá! Tudo bem?")
    }

    func testNulsNeverSurviveInTheLines() {
        XCTAssertFalse(AnswerExtractor.lines(of: "a\u{0}b\n\u{0}\u{0}x\n").joined().contains("\u{0}"))
    }
}

final class RealCodexScreenTests: XCTestCase {
    /// What the real Codex left on screen after answering "responda apenas com a palavra: roxo".
    private let codexScreen = """
    >_ OpenAI Codex (v0.159.3)
    ~

    Welcome to the neighborhood. Lots of characters here.

    › responda apenas com a palavra: roxo

    • roxo

    Worked for 2s • 14:48


    › Ask Codex to do anything

    GPT-5.6-Terra medium · ~ · Responder roxo
    ← for agents · ? for shortcuts
    """

    func testCodexAnswerIsTheReplyNotTheStatusBar() {
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: codexScreen, fixedBox: true), "roxo")
    }

    func testWithoutTheFixedBoxFlagTheStatusBarWouldLeakIn() {
        // The failure the user saw: the placeholder counted as a message.
        XCTAssertTrue(AnswerExtractor.cliAnswer(in: codexScreen).contains("GPT-5.6-Terra"))
    }

    func testCodexKeepsLaterExchangesAndMultiLineReplies() {
        let screen = codexScreen.replacingOccurrences(of: "• roxo\n\nWorked for 2s • 14:48\n", with: "• roxo\n\nWorked for 2s • 14:48\n\n› e agora\n\n• primeira linha\n  segunda linha\n\nWorked for 1m 5s • 14:49\n")
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen, fixedBox: true), "primeira linha\n  segunda linha")
    }

    func testCodexBoxWithNothingSubmittedIsEmpty() {
        let fresh = ">_ OpenAI Codex\n\n› Ask Codex to do anything\n\nGPT-5.6-Terra medium · ~\n← for agents · ? for shortcuts"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: fresh, fixedBox: true), "")
    }

    func testTimingFootersAreRemovedButSimilarSentencesAreKept() {
        let screen = "❯ q\n⏺ We waited for 5 minutes for it.\nBaked for 1s · done\n────────────────────────────────────────────────────────────\n❯"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen), "We waited for 5 minutes for it.")
    }
}


final class SpacesInTUIRepliesTests: XCTestCase {
    /// The user's report: "Olá,Yuri!Testerecebido,…". The gaps in a TUI reply are empty cells.
    func testEmptyCellsBetweenWordsBecomeSpaces() {
        let screen = "❯ oi\n\u{23FA}\u{0}Olá,\u{0}Yuri!\u{0}Teste\u{0}recebido,\u{0}está\u{0}tudo\u{0}funcionando\u{0}por\u{0}aqui.\n\n  Como\u{0}posso\u{0}ajudar?\n────────────────────────────────────────────────────────────\n❯"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen), "Olá, Yuri! Teste recebido, está tudo funcionando por aqui.\n\n  Como posso ajudar?")
    }

    func testCodexWordsKeepTheirSpacesToo() {
        let screen = "› oi\n\n•\u{0}Olá!\u{0}Estou\u{0}funcionando.\u{0}Como\u{0}posso\u{0}ajudar?\n\nWorked for 1s • 14:53\n\n› Ask Codex to do anything\n\nGPT-5.6-Terra medium · ~"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen, fixedBox: true), "Olá! Estou funcionando. Como posso ajudar?")
    }

    func testPaddingAfterAWideGlyphIsNotAGap() {
        XCTAssertEqual(AnswerExtractor.readable("\u{23FA}\u{0}azul"), "\u{23FA}azul")
        XCTAssertEqual(AnswerExtractor.readable("日\u{0}本\u{0}語"), "日本語")
        XCTAssertEqual(AnswerExtractor.readable("🙂\u{0}ok"), "🙂ok")
        XCTAssertEqual(AnswerExtractor.readable("a\u{0}b"), "a b")
        XCTAssertEqual(AnswerExtractor.readable("a\u{0}\u{0}\u{0}b"), "a   b")        // indentation survives
    }

    func testPlainShellTextIsUntouched() {
        XCTAssertEqual(AnswerExtractor.answer(in: "~ ❯ echo\nvamos testar se essa frase está sem espaço\n~ ❯", since: 1, dropsPrompt: true),
                       "vamos testar se essa frase está sem espaço")
    }
}


final class WrappedMessageTests: XCTestCase {
    /// The user's long message wrapped onto a second line, which leaked into the copied answer.
    func testTheWrappedTailOfYourMessageIsNotPartOfTheAnswer() {
        let screen = "❯ responda apenas repetindo esta frase, sem mais nada: o céu está azul e\n  o mar está calmo hoje\n\n\u{23FA}\u{0}o\u{0}céu\u{0}está\u{0}azul\u{0}e\u{0}o\u{0}mar\u{0}está\u{0}calmo\u{0}hoje\n\n✻ Cooked for 1s · done 3:01 PM\n────────────────────────────────────────────────────────────\n❯\n────────────────────────────────────────────────────────────"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen), "o céu está azul e o mar está calmo hoje")
    }

    func testCodexWrappedMessageInsideItsBox() {
        let screen = "› uma pergunta bem longa que quebra\n  em duas linhas\n\n• resposta curta\n\nWorked for 1s • 15:02\n\n› Ask Codex to do anything\n\nGPT-5.6-Terra medium · ~"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen, fixedBox: true), "resposta curta")
    }

    func testAnswersWithBlankLinesInsideStayWhole() {
        let screen = "❯ q\n\n⏺ primeiro\n\n  segundo\n────────────────────────────────────────────────────────────\n❯"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen), "primeiro\n\n  segundo")
    }

    func testNoBlankLineBetweenMessageAndReplyStillWorks() {
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: "❯ q\n⏺ a\n────────────────────────────────────────────────────────────\n❯"), "a")
    }
}


final class ClaudeWrapTests: XCTestCase {
    /// The user's example: "Como posso" / "  ajudar?" and the "◐ medium · /effort" line.
    private func screen(cols: Int) -> (String, Int) {
        let first = "⏺\u{0}Olá!\u{0}Recebi\u{0}o\u{0}\"teste\"\u{0}e\u{0}está\u{0}tudo\u{0}funcionando\u{0}por\u{0}aqui.\u{0}Como\u{0}posso"
        let text = "❯ teste\n\n\(first)\n  ajudar?\n\n\n\n                                         ◐ medium · /effort\n────────────────────────────────────────────────────────────\n❯\n────────────────────────────────────────────────────────────\n"
        return (text, AnswerExtractor.readable(first).count)
    }

    func testTheWrappedSentenceIsJoinedBackAndTheEffortLineIsGone() {
        let (text, firstWidth) = screen(cols: 0)
        let columns = firstWidth + 3                                    // "ajudar?" would not have fitted
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: text, columns: columns),
                       "Olá! Recebi o \"teste\" e está tudo funcionando por aqui. Como posso ajudar?")
    }

    func testWithoutKnowingTheWidthNothingIsJoined() {
        let (text, _) = screen(cols: 0)
        XCTAssertTrue(AnswerExtractor.cliAnswer(in: text).contains("Como posso\n  ajudar?"))
    }

    func testShortIndentedLinesAndCodeAreNeverJoined() {
        let screen = "❯ show\n\n⏺ Here:\n\n  let x = 1\n  print(x)\n  return x\n────────────────────────────────────────────────────────────\n❯"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen, columns: 70), "Here:\n\n  let x = 1\n  print(x)\n  return x")
    }

    func testListsAndHeadingsAreNotMistakenForWraps() {
        let long = String(repeating: "palavra ", count: 9).trimmingCharacters(in: .whitespaces)       // reaches the margin
        let screen = "❯ q\n\n⏺ \(long)\n  - item um\n  1. passo\n  # titulo\n────────────────────────────────────────────────────────────\n❯"
        let answer = AnswerExtractor.cliAnswer(in: screen, columns: long.count + 2)
        XCTAssertTrue(answer.contains("\n  - item um\n  1. passo\n  # titulo"), answer)
    }

    func testAWrappedLineInsideARealParagraphKeepsParagraphBreaks() {
        let line1 = "Esta é a primeira frase bem comprida que enche a linha inteira do terminal agora"
        let screen = "❯ q\n\n⏺ \(line1)\n  continua aqui.\n\n  Segundo parágrafo curto.\n────────────────────────────────────────────────────────────\n❯"
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: screen, columns: line1.count + 3),
                       "\(line1) continua aqui.\n\n  Segundo parágrafo curto.")
    }

    func testEffortLineWithoutTheGlyphMatchStaysIfItIsReplyText() {
        XCTAssertEqual(AnswerExtractor.cliAnswer(in: "❯ q\n\n⏺ use /effort para mudar\n────────────────────────────────────────────────────────────\n❯", columns: 80),
                       "use /effort para mudar")
    }
}


final class ShellWrapTests: XCTestCase {
    func testALongShellLineWrappedByTheTerminalIsJoinedBack() {
        let cols = 20
        let sentence = "Esta linha longa foi quebrada pelo terminal em varias partes"
        // How a terminal wraps it: rows of exactly `cols` characters.
        var rows: [String] = []
        var rest = Substring(sentence)
        while rest.count > cols { rows.append(String(rest.prefix(cols))); rest = rest.dropFirst(cols) }
        rows.append(String(rest))
        let screen = (["~ ❯ echo ..."] + rows + ["~ ❯ "]).joined(separator: "\n")
        XCTAssertEqual(AnswerExtractor.answer(in: screen, since: 1, dropsPrompt: true, columns: cols), sentence)
    }

    func testShortLinesAreNeverJoined() {
        let screen = "~ ❯ ls\nalfa\nbeta\ngama\n~ ❯ "
        XCTAssertEqual(AnswerExtractor.answer(in: screen, since: 1, dropsPrompt: true, columns: 20), "alfa\nbeta\ngama")
    }

    func testTheFinalPromptIsNotGluedToAFullWidthRowBeforeIt() {
        let full = String(repeating: "x", count: 20)
        let screen = "~ ❯ cmd\n\(full)\n~ ❯ "
        XCTAssertEqual(AnswerExtractor.answer(in: screen, since: 1, dropsPrompt: true, columns: 20), full)
    }

    func testWithoutAWidthNothingIsJoined() {
        let full = String(repeating: "x", count: 20)
        XCTAssertEqual(AnswerExtractor.answer(in: "~ ❯ c\n\(full)\nabc\n~ ❯ ", since: 1, dropsPrompt: true), "\(full)\nabc")
    }
}
