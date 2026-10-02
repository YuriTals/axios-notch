import XCTest
import AppKit
@testable import AxiosNotch

final class PasteSupportTests: XCTestCase {
    /// A private pasteboard, so tests never touch the user's clipboard.
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("axios-test-\(UUID().uuidString)"))
    }

    private func pngBytes(color: NSColor = .red, size: Int = 8) -> Data {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill(); image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    func testPlainTextIsLeftToTheTerminal() {
        let pb = makePasteboard(); pb.clearContents(); pb.setString("echo oi", forType: .string)
        XCTAssertEqual(PasteResolver.resolve(pb), .text)
        pb.clearContents()
        XCTAssertEqual(PasteResolver.resolve(pb), .text)                          // empty clipboard
    }

    func testCopiedFilesComeBackAsFiles() {
        let pb = makePasteboard(); pb.clearContents()
        let a = URL(fileURLWithPath: "/tmp/uma foto.png"), b = URL(fileURLWithPath: "/tmp/b.txt")
        pb.writeObjects([a as NSURL, b as NSURL])
        XCTAssertEqual(PasteResolver.resolve(pb), .files([a, b]))
    }

    func testAFileWinsOverItsIconImage() {
        let pb = makePasteboard(); pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/tmp/x.png") as NSURL])
        pb.setData(pngBytes(), forType: .png)                                      // Finder also adds an icon
        if case .files = PasteResolver.resolve(pb) {} else { XCTFail("a file must win over its icon") }
    }

    func testAScreenshotIsAnImageAndTiffIsConvertedToPNG() {
        let pb = makePasteboard(); pb.clearContents()
        pb.setData(NSImage(size: NSSize(width: 4, height: 4), flipped: false) { _ in NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); return true }.tiffRepresentation, forType: .tiff)
        guard case .image(let png) = PasteResolver.resolve(pb) else { return XCTFail("a TIFF-only clipboard is an image") }
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])             // PNG signature
    }

    func testAnImageBesideTextIsStillText() {
        let pb = makePasteboard(); pb.clearContents()
        pb.setString("texto que eu copiei", forType: .string)
        pb.setData(pngBytes(), forType: .png)
        XCTAssertEqual(PasteResolver.resolve(pb), .text)
    }

    func testPathsAreEscapedLikeADragOntoTerminal() {
        XCTAssertEqual(ShellPath.escape("/Users/yuri/Desktop/uma foto (1).png"), "/Users/yuri/Desktop/uma\\ foto\\ \\(1\\).png")
        XCTAssertEqual(ShellPath.escape("/tmp/simple-file_1.2.png"), "/tmp/simple-file_1.2.png")
        XCTAssertEqual(ShellPath.escape("/tmp/a'b\"c&d$e"), "/tmp/a\\'b\\\"c\\&d\\$e")
        XCTAssertEqual(ShellPath.escape("/tmp/ação 写真.png"), "/tmp/ação\\ 写真.png")            // letters stay, the space is escaped
        XCTAssertEqual(ShellPath.joined(["/a b", "/c"]), "/a\\ b /c ")
    }

    func testPastedImagesAreSavedAsPNGAndOldOnesAreRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("axios-pasted-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()

        let old = try XCTUnwrap(PastedImages.save(pngBytes(), in: dir, now: now.addingTimeInterval(-3 * 86_400)))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3 * 86_400)], ofItemAtPath: old.path)
        let stranger = dir.appendingPathComponent("keep-me.txt")                   // not ours: never deleted
        try Data("x".utf8).write(to: stranger)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-9 * 86_400)], ofItemAtPath: stranger.path)

        let fresh = try XCTUnwrap(PastedImages.save(pngBytes(color: .green), in: dir, now: now))
        XCTAssertTrue(fresh.lastPathComponent.hasPrefix("axios-paste-"))
        XCTAssertEqual(fresh.pathExtension, "png")
        XCTAssertEqual(Array(try Data(contentsOf: fresh).prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "an old pasted image should be tidied")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path), "files we did not create must stay")
        XCTAssertNotEqual(fresh, try XCTUnwrap(PastedImages.save(pngBytes(), in: dir, now: now)))   // never overwrites
    }

    // MARK: Dropping files (the same code path the drag uses)

    /// A stand-in for what a drag carries.
    private final class FakeDrop: NSObject, NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggingLocation: NSPoint { .zero }
        var draggedImageLocation: NSPoint { .zero }
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 0 }
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }

    func testDroppingFilesPastesTheirPathsIntoARealShell() throws {
        let store = TerminalSessionStore()
        defer { for key in store.keys { store.close(key) } }
        let key = store.ensureSelected(.shell)
        let view = try XCTUnwrap(store.view(for: key))
        let settle = expectation(description: "shell started"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settle.fulfill() }
        wait(for: [settle], timeout: 4)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("axios drop \(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("uma foto.png")
        try Data("x".utf8).write(to: file)

        let pb = makePasteboard(); pb.clearContents(); pb.writeObjects([file as NSURL])
        let drop = FakeDrop(pasteboard: pb)
        XCTAssertEqual(view.draggingEntered(drop), .copy)
        XCTAssertTrue(view.performDragOperation(drop))

        let echoed = expectation(description: "shell echoes the pasted text"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { echoed.fulfill() }
        wait(for: [echoed], timeout: 4)
        let screen = AnswerExtractor.lines(of: String(data: view.getTerminal().getBufferAsData(), encoding: .utf8) ?? "").joined(separator: "")
        XCTAssertTrue(screen.contains("uma\\ foto.png"), "the escaped path should be on the prompt line: \(screen)")
    }

    func testNonFileDragsAreRefused() {
        let view = ActivityTerminalView(frame: .zero)
        let pb = makePasteboard(); pb.clearContents(); pb.setString("só texto", forType: .string)
        XCTAssertEqual(view.draggingEntered(FakeDrop(pasteboard: pb)), [])
        XCTAssertFalse(view.performDragOperation(FakeDrop(pasteboard: pb)))
    }
}
