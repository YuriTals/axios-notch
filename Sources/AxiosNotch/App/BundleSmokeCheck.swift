import Foundation

/// Runs before AppKit startup, without reading sessions or provider credentials.
enum BundleSmokeCheck {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "AxiosNotch.BundleCheck", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(LoginItem.isBundled, "Run this check from the packaged .app")
        try require(Bundle.main.bundleIdentifier == BuildChannel.bundleIdentifier, "Incorrect bundle identifier")
        if BuildChannel.isTest {
            try require(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Axios Notch Teste", "Missing internal build name")
        }
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
            try require(!value.isEmpty && !value.contains("__"), "Missing package version: \(key)")
        }
        try require(AppResources.url(forResource: "AxiosMark", withExtension: "png") != nil, "Missing AxiosMark.png")
        try require(AppResources.url(forResource: "AppIcon", withExtension: "icns") != nil, "Missing AppIcon.icns")
        guard let directory = FontRegistry.fontsDirectory() else {
            try require(false, "Missing Fonts directory")
            return
        }
        let files = FontRegistry.fontFiles(in: directory)
        try require(files.count == 12, "Expected 12 bundled font files")
        try require(FontRegistry.registerBundledFonts(from: directory) == files.count, "A bundled font could not be registered")
        let available = Set(FontRegistry.availableFamilies())
        try require(FontRegistry.bundledFamilies.allSatisfy { available.contains($0) }, "Missing bundled font family")
    }
}
