import Foundation

/// Poll existing files every refresh; discover new logs with a recursive
/// scan once per 30 seconds instead of traversing the tree every five seconds.
final class SessionFileIndex {
    private let root: URL
    private let calendar: Calendar
    private let scanInterval: TimeInterval
    private let includeHidden: Bool
    private var lastScan: Date?
    private var cached: [URL] = []
    private(set) var scanCount = 0

    init(root: URL, calendar: Calendar, scanInterval: TimeInterval = 30, includeHidden: Bool = false) {
        self.root = root
        self.calendar = calendar
        self.scanInterval = scanInterval
        self.includeHidden = includeHidden
    }

    func files(now: Date) -> [URL] {
        if lastScan.map({ now < $0 || now.timeIntervalSince($0) >= scanInterval }) ?? true {
            scanCount += 1
            lastScan = now
            let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: includeHidden ? [] : [.skipsHiddenFiles])
            cached = enumerator?.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }.map { $0.resolvingSymlinksInPath() } ?? []
        }
        let cutoff = calendar.date(byAdding: .day, value: -91, to: now) ?? .distantPast
        cached = cached.filter { file in
            // URL resource values from a previous enumeration can be stale.
            let fresh = URL(fileURLWithPath: file.path)
            guard let values = try? fresh.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return false }
            return values.isRegularFile == true && (values.contentModificationDate ?? .distantPast) >= cutoff
        }
        return cached
    }
}
