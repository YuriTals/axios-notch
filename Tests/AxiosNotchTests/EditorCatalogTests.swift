import XCTest
@testable import AxiosNotch

final class EditorCatalogTests: XCTestCase {
    func testOnlyInstalledEditorsAreOffered() {
        let installed: Set<String> = ["com.microsoft.VSCode", "com.apple.dt.Xcode"]
        let found = EditorCatalog.installed(locate: { installed.contains($0) ? URL(fileURLWithPath: "/Applications/X.app") : nil })
        XCTAssertEqual(found.map(\.name), ["Visual Studio Code", "Xcode"])
        XCTAssertTrue(EditorCatalog.installed(locate: { _ in nil }).isEmpty)
    }

    func testCatalogHasUniqueIdentifiersAndRealOnesForThisMachine() {
        XCTAssertEqual(Set(EditorCatalog.known.map(\.bundleID)).count, EditorCatalog.known.count)
        XCTAssertEqual(Set(EditorCatalog.known.map(\.name)).count, EditorCatalog.known.count)
        let ids = EditorCatalog.known.map(\.bundleID)
        XCTAssertTrue(ids.contains("com.microsoft.VSCode"))
        XCTAssertTrue(ids.contains("com.todesktop.230313mzl4w4u92"))      // Cursor
    }
}
