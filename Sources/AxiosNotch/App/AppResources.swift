import Foundation

/// Finds bundled files whether the app runs as a packaged `.app` (files sit in
/// `Contents/Resources`) or as a bare SwiftPM binary (files live in the
/// module's resource bundle). SwiftPM's `Bundle.module` can't be used on its
/// own: inside an `.app` its lookup path doesn't exist and it traps.
enum AppResources {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        guard !LoginItem.isBundled else { return nil }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
