import AppKit

/// A code editor the folder of a tab can be opened in.
struct Editor: Equatable, Identifiable {
    let name: String
    let bundleID: String
    var id: String { bundleID }
}

/// The editors the "open folder" menu knows about. Only those actually
/// installed on this Mac are offered.
enum EditorCatalog {
    static let known: [Editor] = [
        Editor(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        Editor(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        Editor(name: "Windsurf", bundleID: "com.exafunction.windsurf"),
        Editor(name: "Zed", bundleID: "dev.zed.Zed"),
        Editor(name: "Sublime Text", bundleID: "com.sublimetext.4"),
        Editor(name: "Xcode", bundleID: "com.apple.dt.Xcode"),
        Editor(name: "WebStorm", bundleID: "com.jetbrains.WebStorm"),
        Editor(name: "Nova", bundleID: "com.panic.Nova"),
    ]

    static func installed(locate: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) -> [Editor] {
        known.filter { locate($0.bundleID) != nil }
    }
}

/// Opens a folder in Finder or in an editor.
enum FolderOpener {
    static func showInFinder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    static func open(_ path: String, in editor: Editor) {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
