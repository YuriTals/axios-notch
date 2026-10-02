import Foundation

/// One tab as it was when the app last ran: which tool, and the folder it was in.
/// Only this is remembered — never the conversation or the running process.
struct SavedTab: Codable, Equatable {
    /// "claude", "codex", or nil for the plain shell.
    var provider: String?
    var directory: String?
    var wasSelected: Bool
}

/// The tabs to bring back on the next launch.
struct SavedTabs: Codable, Equatable {
    var tabs: [SavedTab] = []

    private static let key = "savedTabs"

    static func load(defaults: UserDefaults = .standard) -> SavedTabs {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedTabs.self, from: $0) } ?? SavedTabs()
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    /// The tabs worth reopening: at most `perTool` per tool, a folder that no
    /// longer exists falls back to the home folder (nil), and unknown tools
    /// (a future version's, or junk) are skipped.
    func restorable(perTool: Int = SessionKey.maxPerProvider,
                    customToolIDs: Set<String> = Set(AppSettings.shared.customTools.map(\.id)),
                    folderExists: (String) -> Bool = { var isDir: ObjCBool = false
                        return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue }) -> [SavedTab] {
        var counts: [String: Int] = [:]
        var result: [SavedTab] = []
        for tab in tabs {
            if let name = tab.provider {
                guard let tool = Tool(id: name) else { continue }                  // a tool this version doesn't know
                if case .custom(let id) = tool, !customToolIDs.contains(id) { continue }   // the user removed it meanwhile
            }
            let id = tab.provider ?? "shell"
            guard counts[id, default: 0] < perTool else { continue }
            counts[id, default: 0] += 1
            var copy = tab
            if let directory = tab.directory, !folderExists(directory) { copy.directory = nil }
            result.append(copy)
        }
        return result
    }
}
