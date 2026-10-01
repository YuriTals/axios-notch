import Foundation

/// Reads only the bytes appended to a set of files since the last call,
/// splitting them into complete lines. Used to watch growing session logs
/// (Claude Code, Codex) without re-reading the whole file on every poll.
///
/// A partial line at the end of a read (the writer hasn't flushed its
/// trailing newline yet) is left unconsumed: the offset only advances past
/// the last complete line, so the partial bytes are re-read next time
/// together with whatever gets appended after them.
final class JSONLTailReader {
    private var offsets: [URL: UInt64] = [:]

    /// Returns the complete lines appended to `file` since the last call for
    /// that URL. Returns `nil` if the file can no longer be opened, and `[]`
    /// if there is nothing new (or only an unterminated partial line) yet.
    func newLines(in file: URL) -> [Data]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let previousOffset = offsets[file] ?? 0
        guard let size = try? handle.seekToEnd() else { return nil }

        guard size >= previousOffset else {
            // File was truncated or replaced; start over from the top.
            offsets[file] = 0
            return newLines(in: file)
        }
        guard size > previousOffset else { return [] }

        try? handle.seek(toOffset: previousOffset)
        let data = handle.readDataToEndOfFile()
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return [] }

        let consumed = data[data.startIndex...lastNewline]
        offsets[file] = previousOffset + UInt64(consumed.count)
        return consumed.split(separator: 0x0A).map { Data($0) }
    }

    /// Forgets a file, so the next call re-reads it from the start.
    func forget(_ file: URL) {
        offsets.removeValue(forKey: file)
    }
}
