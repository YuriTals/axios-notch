import Foundation

/// The folders sessions were last used in, most recent first, so a new session
/// can be opened in one with a click. Pure list logic over `UserDefaults`.
struct RecentProjects {
    static let limit = 8
    private static let key = "recentProjects"

    private(set) var paths: [String]

    init(paths: [String] = []) { self.paths = paths }

    static func load(defaults: UserDefaults = .standard) -> RecentProjects {
        RecentProjects(paths: defaults.stringArray(forKey: key) ?? [])
    }

    func save(defaults: UserDefaults = .standard) { defaults.set(paths, forKey: Self.key) }

    /// Puts `path` first. The home folder and the root say nothing about a
    /// project, and a path that is already listed just moves up.
    mutating func record(_ path: String, home: String = NSHomeDirectory()) {
        let clean = Self.normalized(path)
        guard ProcessDirectory.projectName(forPath: clean, home: home) != nil else { return }
        paths.removeAll { $0 == clean }
        paths.insert(clean, at: 0)
        if paths.count > Self.limit { paths.removeLast(paths.count - Self.limit) }
    }

    mutating func clear() { paths = [] }

    /// What to offer in the menu: folders that still exist, minus any the
    /// caller wants hidden (the folder the current tab is already in).
    func suggestions(excluding hidden: Set<String> = [], max: Int = 5,
                     exists: (String) -> Bool = { var isDir: ObjCBool = false
                         return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue }) -> [String] {
        Array(paths.filter { !hidden.contains($0) && exists($0) }.prefix(max))
    }

    static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
