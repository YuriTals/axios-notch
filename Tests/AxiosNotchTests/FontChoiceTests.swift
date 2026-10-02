import XCTest
import AppKit
@testable import AxiosNotch

final class FontChoiceTests: XCTestCase {
    func testOnlyInstalledFontsAreOffered() {
        let minimal = FontChoice.available(families: ["Menlo", "Monaco"])
        XCTAssertEqual(minimal, [.auto, .sfMono, .menlo, .monaco])           // auto and system mono always

        let withNerd = FontChoice.available(families: ["Menlo", "JetBrainsMono Nerd Font Mono", "Hack"])
        XCTAssertTrue(withNerd.contains(.jetbrains))                         // the Nerd build counts
        XCTAssertTrue(withNerd.contains(.hack))
        XCTAssertFalse(withNerd.contains(.firaCode))
        XCTAssertEqual(Set(FontChoice.allCases.map(\.label)).count, FontChoice.allCases.count)
    }

    func testEachChoiceResolvesToTheRightMonospacedFont() {
        let real = FontChoice.available()
        for choice in real {
            let font = TerminalFont.resolve(choice: choice, size: 13)
            XCTAssertEqual(font.pointSize, 13, accuracy: 0.01, "\(choice)")
            XCTAssertTrue(font.isFixedPitch || font.fontName.lowercased().contains("mono") || font.familyName?.contains("Nerd") == true,
                          "\(choice) -> \(font.fontName)")
        }
        XCTAssertTrue(TerminalFont.resolve(choice: .menlo, size: 12).fontName.hasPrefix("Menlo"))
        XCTAssertTrue(TerminalFont.resolve(choice: .monaco, size: 12).fontName.hasPrefix("Monaco"))
    }

    func testMissingFontFallsBackInsteadOfBreaking() {
        let font = TerminalFont.resolve(choice: .cascadia, size: 14, families: ["Menlo"])
        XCTAssertEqual(font.pointSize, 14, accuracy: 0.01)
        XCTAssertNotNil(font.familyName)
    }

    func testPlainFontsGetANerdFallbackForPromptIcons() {
        let families = FontRegistry.availableFamilies()
        guard families.contains(where: { $0.localizedCaseInsensitiveContains("Nerd Font") }) else { return }   // none installed here
        let menlo = TerminalFont.resolve(choice: .menlo, size: 13)
        let cascade = menlo.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor]
        XCTAssertFalse(cascade?.isEmpty ?? true, "Menlo should carry a Nerd Font cascade")
    }

    func testChoicePersistsAndJunkFallsBack() {
        let suite = "axios-font-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.terminalFont, .auto)
        first.terminalFont = .menlo
        XCTAssertEqual(AppSettings(defaults: defaults).terminalFont, .menlo)
        defaults.set("comic-sans", forKey: "terminalFont")
        XCTAssertEqual(AppSettings(defaults: defaults).terminalFont, .auto)
    }
}

final class BundledFontsTests: XCTestCase {
    func testTheFontFilesShipWithTheApp() throws {
        let directory = try XCTUnwrap(FontRegistry.fontsDirectory(), "no resource directory")
        let files = FontRegistry.fontFiles(in: directory).map(\.lastPathComponent)
        // Six families × Regular and Bold.
        XCTAssertEqual(files.filter { $0.contains("NerdFontMono") }.count, 12, "found: \(files)")
        for family in ["FiraCode", "JetBrainsMono", "SauceCodePro", "Hack", "CaskaydiaCove", "BlexMono"] {
            XCTAssertTrue(files.contains("\(family)NerdFontMono-Regular.ttf"), family)
            XCTAssertTrue(files.contains("\(family)NerdFontMono-Bold.ttf"), family)
        }
    }

    func testEveryBundledFamilyRegistersAndResolvesWithoutAnythingInstalled() throws {
        XCTAssertEqual(FontRegistry.registerBundledFonts(), 12)
        XCTAssertEqual(FontRegistry.registerBundledFonts(), 12)             // calling again is harmless

        let families = FontRegistry.availableFamilies()
        for family in FontRegistry.bundledFamilies { XCTAssertTrue(families.contains(family), "\(family) not registered") }

        for choice in [FontChoice.jetbrains, .firaCode, .sourceCode, .hack, .cascadia, .plex, .auto] {
            // Pretend the Mac has none of them installed: the bundled ones must still resolve.
            let font = TerminalFont.resolve(choice: choice, size: 13, families: families)
            XCTAssertTrue(font.familyName?.contains("Nerd Font Mono") ?? false, "\(choice) -> \(font.fontName)")
            XCTAssertTrue(choice.isBundled || choice == .auto)
        }
        XCTAssertTrue(TerminalFont.resolve(choice: .jetbrains, size: 13, families: families).fontName.hasPrefix("JetBrainsMono"))
        XCTAssertTrue(TerminalFont.resolve(choice: .hack, size: 13, families: families).fontName.hasPrefix("Hack"))
    }

    func testTheSixDeveloperFontsAreOfferedEvenOnAFreshMac() {
        let bundledOnly = FontChoice.available(families: FontRegistry.bundledFamilies)
        XCTAssertTrue(Set(bundledOnly).isSuperset(of: [.auto, .sfMono, .jetbrains, .firaCode, .sourceCode, .hack, .cascadia, .plex]))
        XCTAssertFalse(bundledOnly.contains(.menlo))                         // Apple's, not ours to ship
    }

    func testLicencesShipAlongside() throws {
        let directory = try XCTUnwrap(FontRegistry.fontsDirectory())
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).joined(separator: " ")
        for licence in ["FiraCode-OFL", "JetBrainsMono-OFL", "SourceCodePro-OFL", "Hack-LICENSE", "CascadiaCode-OFL", "IBMPlexMono-OFL"] {
            XCTAssertTrue(names.contains(licence), "missing \(licence)")
        }
    }
}
