import Foundation

/// Pulls "the last answer" out of a terminal's text: everything printed after
/// the user last pressed Enter, minus the decoration around it.
///
/// A terminal is not a chat, so this is the best honest definition of an
/// answer: the output since the last Enter. For a shell that is the command's
/// output; for Claude or Codex it is what they printed in reply.
enum AnswerExtractor {
    /// The lines of a buffer dump, with the empty tail (unused screen rows)
    /// removed.
    static func lines(of bufferText: String) -> [String] {
        var all = readable(bufferText).components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\r", with: "") }
        while let last = all.last, last.trimmingCharacters(in: .whitespaces).isEmpty { all.removeLast() }
        return all
    }

    /// Turns the terminal's empty cells back into text. Claude and Codex draw
    /// their text by moving the cursor, so the gaps between words are *empty
    /// cells* (NUL in the dump), not space characters: they are spaces. The one
    /// exception is the padding cell that follows a double-width glyph (the
    /// reply bullet ⏺, emoji, CJK), which is not a gap and must go.
    static func readable(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            if scalar == "\u{0}" {
                if let previous, isDoubleWidth(previous) { continue }
                output.append(" ")
                previous = " "
            } else {
                output.append(scalar)
                previous = scalar
            }
        }
        return String(output)
    }

    /// Scalars a terminal draws two cells wide (the common East Asian wide
    /// ranges and emoji, plus the ⏩…⏺ symbols Claude uses for its bullet).
    static func isDoubleWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF,
             0x23E9...0x23FA, 0x2705, 0x2728, 0x274C, 0x2B50, 0x2B55:
            return true
        default:
            return false
        }
    }

    /// How many lines the buffer holds right now — the marker taken when the
    /// user presses Enter.
    static func lineCount(of bufferText: String) -> Int { lines(of: bufferText).count }

    /// The answer: lines after `marker`, cleaned.
    /// - Parameter dropsPrompt: a plain shell ends with its next prompt, which is
    ///   not part of the answer.
    /// - Parameter columns: the terminal width. A shell's output that is longer
    ///   than a row is wrapped by the terminal itself, so a row that fills the
    ///   whole width continues on the next one and is joined back.
    static func answer(in bufferText: String, since marker: Int, dropsPrompt: Bool, columns: Int? = nil) -> String {
        var result = Array(lines(of: bufferText).dropFirst(max(marker, 0)))
        if dropsPrompt, !result.isEmpty { result.removeLast() }
        if let columns { result = rejoinTerminalWraps(result, columns: columns) }
        result = result.filter { !isDecoration($0) }.map { String($0.reversed().drop(while: { $0 == " " }).reversed()) }
        while let first = result.first, first.isEmpty { result.removeFirst() }
        while let last = result.last, last.isEmpty { result.removeLast() }
        return result.joined(separator: "\n")
    }

    /// The answer in a Claude Code / Codex screen.
    ///
    /// These tools redraw their own screen in place, with the input box pinned
    /// to the bottom, so "output since Enter" does not work (the answer lands
    /// above the box, inside rows that were already on screen). Instead: find
    /// the last message the user sent (a line starting with the tool's prompt
    /// glyph and some text), and take what follows it until the input box begins
    /// (a long horizontal rule).
    ///
    /// - Parameter fixedBox: Codex keeps its input box (a prompt line with
    ///   placeholder text, plus a status bar) at the very bottom and has no
    ///   horizontal rule above it, so the *last* prompt line is that box: skip
    ///   it and stop the answer right before it.
    /// - Parameter columns: the terminal's width. These tools wrap their text at
    ///   it, so a reply arrives cut into lines in the middle of sentences;
    ///   knowing the width lets those lines be joined back (see `rejoinWrapped`).
    static func cliAnswer(in bufferText: String, fixedBox: Bool = false, columns: Int? = nil) -> String {
        let all = lines(of: bufferText)
        let promptGlyphs: [Character] = ["❯", "›"]

        func isUserMessage(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first, promptGlyphs.contains(first) else { return false }
            return !trimmed.dropFirst().trimmingCharacters(in: .whitespaces).isEmpty
        }
        /// "────────────": the top of the input box (or a separator).
        func isRule(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 12 && trimmed.allSatisfy { "─━═-".contains($0) }
        }

        func startsWithPrompt(_ line: String) -> Bool {
            guard let first = line.trimmingCharacters(in: .whitespaces).first else { return false }
            return promptGlyphs.contains(first)
        }
        // Where the input box begins, when the tool pins one at the bottom.
        let boxStart: Int? = fixedBox ? all.indices.last(where: { startsWithPrompt(all[$0]) }) : nil

        for start in all.indices.reversed() where isUserMessage(all[start]) && start != boxStart {
            // A long message wraps onto more lines, indented, with no prompt glyph;
            // those belong to the message. The reply starts after the blank line
            // that follows it (when there is no blank line, right after the prompt).
            var replyStart = start + 1
            func startsWithReplyBullet(_ line: String) -> Bool {
                guard let first = line.trimmingCharacters(in: .whitespaces).first else { return false }
                return "●⏺•".contains(first)
            }
            // A reply bullet right under the message means nothing wrapped.
            if start + 1 < all.count, !startsWithReplyBullet(all[start + 1]) {
                for index in (start + 1)..<all.count {
                    if index == boxStart || isRule(all[index]) { break }
                    if all[index].trimmingCharacters(in: .whitespaces).isEmpty { replyStart = index + 1; break }
                }
            }
            var body: [String] = []
            for index in replyStart..<max(replyStart, all.count) {
                if index == boxStart { break }                              // the fixed input box
                if isRule(all[index]) { break }                             // a ruled input box starts here
                body.append(all[index])
            }
            let text = clean(body, columns: columns)
            if !text.isEmpty { return text }                               // else: that was text typed in the box; look further up
        }
        return ""
    }

    /// Cleanup shared by the CLI case: drop frames, the assistant bullet
    /// (`● `), spinner/summary lines (`✻ Baked for 1s`), trailing spaces and
    /// blank edges.
    private static func clean(_ raw: [String], columns: Int?) -> String {
        var result = raw.filter { !isDecoration($0) }
        if let columns { result = rejoinWrapped(result, columns: columns) }
        result = result.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("✻") || trimmed.hasPrefix("✽") || trimmed.hasPrefix("✶") { return nil }
            // The effort / mode indicator Claude draws above its input box: "◐ medium · /effort".
            if let glyph = trimmed.first, "◐◑◒◓".contains(glyph), trimmed.contains("/effort") { return nil }
            // "Worked for 2s • 14:48" (Codex), "Baked for 1s · done" (Claude): timing footers.
            if trimmed.range(of: #"^\S+ for \d+[smh]( \d+[smh])*\s*[·•]"#, options: .regularExpression) != nil { return nil }
            return line
        }
        // The bullet that marks where the assistant starts talking: ● / ⏺ (Claude), • (Codex).
        if let first = result.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            // The terminal pads the bullet with an empty cell, so what is left may
            // have no space after it ("⏺azul").
            let line = result[first].drop(while: { $0 == " " })
            if let glyph = line.first, "●⏺•".contains(glyph) {
                result[first] = String(line.dropFirst().drop(while: { $0 == " " }))
            }
        }
        result = result.map { String($0.reversed().drop(while: { $0 == " " }).reversed()) }
        while let first = result.first, first.isEmpty { result.removeFirst() }
        while let last = result.last, last.isEmpty { result.removeLast() }
        return result.joined(separator: "\n")
    }

    /// Joins rows the terminal wrapped on its own: a row that fills the whole
    /// width carries on in the row below, with no space added (a space that fell
    /// on the boundary is kept where it is).
    static func rejoinTerminalWraps(_ lines: [String], columns: Int) -> [String] {
        guard columns > 0 else { return lines }
        var result: [String] = []
        var previousWasFull = false
        for line in lines {
            if previousWasFull, !result.isEmpty {
                result[result.count - 1] += line
            } else {
                result.append(line)
            }
            previousWasFull = line.count >= columns
        }
        return result
    }

    /// Joins the lines a tool broke in the middle of a sentence. Claude and
    /// Codex wrap their text at the terminal width and indent the continuation
    /// by two spaces, so a line counts as a wrap of the one above when it is
    /// indented by exactly two, and the first word of it would not have fitted
    /// on the line above. Code, lists and short lines are left alone.
    static func rejoinWrapped(_ lines: [String], columns: Int) -> [String] {
        var result: [String] = []
        for line in lines {
            guard let previous = result.last, isContinuation(line, of: previous, columns: columns) else {
                result.append(line)
                continue
            }
            result[result.count - 1] = previous + " " + line.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func isContinuation(_ line: String, of previous: String, columns: Int) -> Bool {
        guard line.hasPrefix("  "), !line.hasPrefix("   ") else { return false }          // indented by exactly two
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !previous.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let structural = ["- ", "* ", "• ", "#", "```", "|", ">"]
        if structural.contains(where: { text.hasPrefix($0) }) { return false }
        if text.first?.isNumber == true, text.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil { return false }
        let firstWord = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
        return previous.count + 1 + firstWord.count > columns - 2                          // it did not fit up there
    }

    /// Box-drawing rules and frames (Claude/Codex input boxes, separators).
    private static func isDecoration(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let drawing = CharacterSet(charactersIn: "─━│┃┌┐└┘├┤┬┴┼╭╮╯╰═║╔╗╚╝╠╣╦╩╬ ")
        return trimmed.unicodeScalars.allSatisfy { drawing.contains($0) }
    }
}
