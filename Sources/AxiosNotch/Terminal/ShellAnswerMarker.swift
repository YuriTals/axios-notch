import Foundation
import SwiftTerm

/// Tracks the submitted prompt as rows reflow or leave the scrollback buffer.
final class ShellAnswerMarker {
    private let buffer: ObjectIdentifier
    private let line: BufferLine?
    private let prompt: String?
    private let promptPrefix: String
    private let rowCount: Int
    private let trimmed: Int

    init(terminal: Terminal) {
        buffer = ObjectIdentifier(terminal.buffer)
        rowCount = AnswerExtractor.lineCount(of: String(data: terminal.getBufferAsData(), encoding: .utf8) ?? "")
        trimmed = terminal.buffer.totalLinesTrimmed
        line = terminal.bufferLine(atRow: rowCount - 1)
        prompt = line?.translateToString(trimRight: true)
        // Right prompts are separated by padding and may disappear on Enter.
        promptPrefix = AnswerExtractor.readable(prompt ?? "").trimmingCharacters(in: .whitespaces)
            .components(separatedBy: "  ").first ?? ""
    }

    func rowOffset(in terminal: Terminal) -> Int {
        let currentTrimmed = terminal.buffer.totalLinesTrimmed
        guard ObjectIdentifier(terminal.buffer) == buffer, currentTrimmed >= trimmed else { return 0 }
        let count = AnswerExtractor.lineCount(of: String(data: terminal.getBufferAsData(), encoding: .utf8) ?? "")
        if let line {
            for row in 0..<count {
                if terminal.bufferLine(atRow: row) === line,
                   !line.translateToString(trimRight: true).trimmingCharacters(in: .whitespaces).isEmpty {
                    // The shell can redraw this row while echoing the command.
                    let text = AnswerExtractor.readable(line.translateToString(trimRight: true)).trimmingCharacters(in: .whitespaces)
                    if currentTrimmed == trimmed && text.hasPrefix(promptPrefix) || line.translateToString(trimRight: true) == prompt { return row + 1 }
                }
            }
        }
        // A clear/reset invalidates the prompt without trimming scrollback.
        if currentTrimmed == trimmed { return 0 }
        return max(0, rowCount - (currentTrimmed - trimmed))
    }
}
