import XCTest
@testable import AxiosNotch

final class LiquidGlassTests: XCTestCase {
    func testOpacityIsClampedToTheAllowedRange() {
        XCTAssertEqual(AppSettings.clampedOpacity(0), AppSettings.opacityRange.lowerBound)
        XCTAssertEqual(AppSettings.clampedOpacity(5), 1)
        XCTAssertEqual(AppSettings.clampedOpacity(0.6), 0.6)
    }

    @MainActor
    func testTerminalStaysOpaqueUnlessGlassIsActuallyOn() {
        let settings = AppSettings.shared
        let (glass, opacity) = (settings.liquidGlass, settings.terminalOpacity)
        defer { settings.liquidGlass = glass; settings.terminalOpacity = opacity }

        settings.terminalOpacity = 0.5
        settings.liquidGlass = false
        XCTAssertEqual(settings.effectiveTerminalOpacity, 1)

        settings.liquidGlass = true
        XCTAssertEqual(settings.effectiveTerminalOpacity, AppSettings.glassSupported ? 0.5 : 1)
    }
}
