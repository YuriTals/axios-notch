import Darwin
import Foundation

/// Where a process is working, so a finished answer can say *which project*.
enum ProcessDirectory {
    /// The current working directory of `pid`, if the system will tell us.
    static func current(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// A short project label for a directory: its folder name. The home
    /// folder and the filesystem root say nothing about a project, so they
    /// give `nil`.
    static func projectName(forPath path: String, home: String = NSHomeDirectory()) -> String? {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let homeTrimmed = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        guard trimmed != "/", trimmed != homeTrimmed, !trimmed.isEmpty else { return nil }
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
