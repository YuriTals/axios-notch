import XCTest
import SwiftTerm
@testable import AxiosNotch

final class TerminalThemeTests: XCTestCase {
    func testHexParsing() {
        XCTAssertTrue(TerminalTheme.rgb("#282a36") == (40, 42, 54))
        XCTAssertTrue(TerminalTheme.rgb("ffffff") == (255, 255, 255))
        XCTAssertTrue(TerminalTheme.rgb("nope") == (0, 0, 0))
        XCTAssertTrue(TerminalTheme.rgb("#12345") == (0, 0, 0))
    }

    func testEveryThemeIsComplete() {
        for theme in TerminalTheme.allCases {
            let p = theme.palette
            XCTAssertEqual(p.background.count, 7, "\(theme)")
            XCTAssertEqual(p.foreground.count, 7, "\(theme)")
            if let ansi = p.ansi {
                XCTAssertEqual(ansi.count, 16, "\(theme) needs exactly 16 ANSI colours")
                XCTAssertTrue(ansi.allSatisfy { $0.hasPrefix("#") && $0.count == 7 && Int($0.dropFirst(), radix: 16) != nil }, "\(theme)")
            }
        }
        XCTAssertEqual(Set(TerminalTheme.allCases.map(\.label)).count, TerminalTheme.allCases.count)
        XCTAssertNil(TerminalTheme.standard.palette.ansi)                  // uses the terminal's own palette
    }

    func testApplyingAThemeChangesTheTerminalAndDefaultRestoresIt() {
        let view = LocalProcessTerminalView(frame: .zero)
        TerminalTheme.standard.apply(to: view)
        let original = view.nativeBackgroundColor.usingColorSpace(.sRGB)

        TerminalTheme.dracula.apply(to: view)
        let dracula = view.nativeBackgroundColor.usingColorSpace(.sRGB)
        XCTAssertEqual(Double(dracula?.redComponent ?? 0), 40.0 / 255, accuracy: 0.01)
        XCTAssertEqual(Double(dracula?.blueComponent ?? 0), 54.0 / 255, accuracy: 0.01)

        TerminalTheme.standard.apply(to: view)
        XCTAssertEqual(view.nativeBackgroundColor.usingColorSpace(.sRGB), original)
        XCTAssertEqual(Double(original?.redComponent ?? 1), 0, accuracy: 0.01)         // black
    }

    func testThemePersists() {
        let suite = "axios-theme-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.terminalTheme, .standard)
        first.terminalTheme = .nord
        XCTAssertEqual(AppSettings(defaults: defaults).terminalTheme, .nord)
        defaults.set("bogus", forKey: "terminalTheme")
        XCTAssertEqual(AppSettings(defaults: defaults).terminalTheme, .standard)
        TerminalSessionStore.shared.refreshThemes()                          // no sessions: must be a no-op
    }
}
