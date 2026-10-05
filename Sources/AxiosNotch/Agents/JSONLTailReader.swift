import Darwin
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
    struct Read {
        let lines: [Data]
        let wasReset: Bool
    }

    private struct State {
        let identity: String
        let size: UInt64
        let modified: TimeInterval
        let offset: UInt64
        let checkpoint: Data
    }
    private var states: [URL: State] = [:]
    var trackedFileCount: Int { states.count }

    /// Returns the complete lines appended to `file` since the last call for
    /// that URL. Returns `nil` if the file can no longer be opened, and `[]`
    /// if there is nothing new (or only an unterminated partial line) yet.
    func read(in file: URL) -> Read? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(handle.fileDescriptor, &attributes) == 0 else { return nil }
        let identity = "\(attributes.st_dev):\(attributes.st_ino)"
        let modified = Double(attributes.st_mtimespec.tv_sec) + Double(attributes.st_mtimespec.tv_nsec) / 1e9
        guard let size = try? handle.seekToEnd() else { return nil }
        let previous = states[file]
        var reset = previous.map {
            $0.identity != identity || size < $0.size ||
                (size == $0.size && modified != $0.modified)
        } ?? false

        if let previous, !reset, size == previous.size, modified == previous.modified {
            return Read(lines: [], wasReset: false)
        }

        do {
            // A rewrite can grow too: verify the consumed boundary before
            // assuming that new bytes are an append.
            if let previous, !reset, !previous.checkpoint.isEmpty, modified != previous.modified {
                try handle.seek(toOffset: previous.offset - UInt64(previous.checkpoint.count))
                reset = try handle.read(upToCount: previous.checkpoint.count) != previous.checkpoint
            }
            let offset = reset ? 0 : (previous?.offset ?? 0)
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            let consumedCount = data.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
            let nextOffset = offset + UInt64(consumedCount)
            let count = Int(min(64, nextOffset))
            try handle.seek(toOffset: nextOffset - UInt64(count))
            let checkpoint = try handle.read(upToCount: count) ?? Data()
            states[file] = State(identity: identity, size: size, modified: modified,
                                 offset: nextOffset, checkpoint: checkpoint)
            return Read(lines: data.prefix(consumedCount).split(separator: 0x0A).map { Data($0) }, wasReset: reset)
        } catch { return nil }
    }

    func newLines(in file: URL) -> [Data]? { read(in: file)?.lines }

    /// Forgets a file, so the next call re-reads it from the start.
    func forget(_ file: URL) {
        states[file] = nil
    }

    func retainFiles(_ files: Set<URL>) { states = states.filter { files.contains($0.key) } }
}
