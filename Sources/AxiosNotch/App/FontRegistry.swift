import CoreText
import Foundation

/// Makes the monospaced fonts shipped inside the app usable without installing
/// anything (JetBrains Mono, Fira Code, Source Code Pro, Hack, Cascadia Code and
/// IBM Plex Mono, as Nerd Font builds; licences are shipped alongside): they are registered for this process only (never copied into the
/// user's Font Book), and disappear when the app quits.
enum FontRegistry {
    /// Where the bundled font files live: `Contents/Resources/Fonts` in the
    /// packaged app, the SwiftPM resource bundle when run from the command line.
    static func fontsDirectory() -> URL? {
        if let resources = Bundle.main.resourceURL {
            let packaged = resources.appendingPathComponent("Fonts", isDirectory: true)
            if FileManager.default.fileExists(atPath: packaged.path) { return packaged }
        }
        guard !LoginItem.isBundled else { return nil }
        // SwiftPM flattens resource folders, so the fonts sit at the bundle's top level.
        return Bundle.module.resourceURL
    }

    /// The `.ttf`/`.otf` files in `directory`.
    static func fontFiles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The family names the bundled files provide.
    static let bundledFamilies = [
        "FiraCode Nerd Font Mono", "JetBrainsMono Nerd Font Mono", "SauceCodePro Nerd Font Mono",
        "Hack Nerd Font Mono", "CaskaydiaCove Nerd Font Mono", "BlexMono Nerd Font Mono",
    ]

    /// Registers every bundled font and returns how many are now available.
    /// Safe to call more than once; fonts already registered count as available.
    @discardableResult
    static func registerBundledFonts(from directory: URL? = fontsDirectory()) -> Int {
        guard let directory else { return 0 }
        var available = 0
        for file in fontFiles(in: directory) {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) {
                available += 1
            } else if let code = (error?.takeRetainedValue() as Error?).map({ ($0 as NSError).code }),
                      code == CTFontManagerError.alreadyRegistered.rawValue {
                available += 1
            }
        }
        return available
    }
}
