import XCTest
import AppKit
@testable import AxiosNotch

final class FileDragTests: XCTestCase {
    // A notch at the top-centre of a 2056-wide screen (AppKit: y grows upward).
    private let notch = CGRect(x: 928, y: 1248, width: 200, height: 32)
    private let surface = CGRect(x: 858, y: 1130, width: 340, height: 150)

    private func action(files: Bool = true, at p: CGPoint, open: Bool = false, idle: Bool = true) -> FileDragRules.Action {
        FileDragRules.action(isFileDrag: files, pointer: p, notch: notch, openSurface: open ? surface : nil, isDropOpen: open, isIdle: idle)
    }

    func testDraggingAFileNearTheNotchOpensTheTargets() {
        XCTAssertEqual(action(at: CGPoint(x: 1028, y: 1270)), .open)               // on the notch
        XCTAssertEqual(action(at: CGPoint(x: 900, y: 1230)), .open)                // a little to the side and below
    }

    func testFarFromTheNotchNothingHappens() {
        XCTAssertEqual(action(at: CGPoint(x: 1028, y: 600)), .none)
        XCTAssertEqual(action(at: CGPoint(x: 100, y: 1270)), .none)
        XCTAssertEqual(action(at: CGPoint(x: 1028, y: 1100)), .none)               // just below the trigger strip
    }

    func testOnlyFileDragsCountAndNothingIsInterruptedWhenBusy() {
        XCTAssertEqual(action(files: false, at: CGPoint(x: 1028, y: 1270)), .none)  // a text/window drag
        XCTAssertEqual(action(at: CGPoint(x: 1028, y: 1270), idle: false), .none)  // picker/terminal already open
    }

    func testTheTargetsStayWhileThePointerIsNearAndCloseWhenItLeaves() {
        XCTAssertEqual(action(at: CGPoint(x: 1028, y: 1180), open: true), .none)   // on the tiles
        XCTAssertEqual(action(at: CGPoint(x: 1210, y: 1180), open: true), .none)   // a bit outside: forgiven
        XCTAssertEqual(action(at: CGPoint(x: 1400, y: 1180), open: true), .close)
        XCTAssertEqual(action(at: CGPoint(x: 1028, y: 800), open: true), .close)
        XCTAssertEqual(action(files: false, at: CGPoint(x: 1028, y: 1180), open: true), .close)   // drag cancelled
    }

    func testReadsFileURLsFromAPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("axios-drag-\(UUID().uuidString)"))
        pb.clearContents()
        XCTAssertTrue(FileDrag.fileURLs(in: pb).isEmpty)
        pb.setString("só texto", forType: .string)
        XCTAssertTrue(FileDrag.fileURLs(in: pb).isEmpty)
        pb.clearContents()
        let a = URL(fileURLWithPath: "/tmp/a b.png"), b = URL(fileURLWithPath: "/tmp/c.txt")
        pb.writeObjects([a as NSURL, b as NSURL])
        XCTAssertEqual(FileDrag.fileURLs(in: pb), [a, b])
    }

    func testLoadsFileURLsFromDropProvidersInOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("axios-providers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = ["um.png", "dois.txt", "três.pdf"].map { dir.appendingPathComponent($0) }
        for file in files { try Data("x".utf8).write(to: file) }
        let providers = try files.map { try XCTUnwrap(NSItemProvider(contentsOf: $0)) }

        let done = expectation(description: "loaded")
        var loaded: [URL] = []
        FileDrag.loadFileURLs(from: providers) { loaded = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(loaded.map { $0.resolvingSymlinksInPath().path }, files.map { $0.resolvingSymlinksInPath().path })

        let none = expectation(description: "nothing")
        FileDrag.loadFileURLs(from: [NSItemProvider(object: "texto" as NSString)]) { XCTAssertTrue($0.isEmpty); none.fulfill() }
        wait(for: [none], timeout: 5)
    }

    func testAttachingToAShellPastesTheEscapedPathOnceItIsReady() throws {
        let store = TerminalSessionStore()
        defer { for key in store.keys { store.close(key) } }
        store.attach(paths: ["/tmp/uma foto.png"], to: nil)                          // creates the tab, waits, pastes
        let key = try XCTUnwrap(store.selectedKey(for: nil))
        let view = try XCTUnwrap(store.view(for: key))
        let settle = expectation(description: "pasted"); DispatchQueue.main.asyncAfter(deadline: .now() + 3) { settle.fulfill() }
        wait(for: [settle], timeout: 6)
        let screen = String(data: view.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(screen.contains("/tmp/uma\\ foto.png"), screen)
    }
}
