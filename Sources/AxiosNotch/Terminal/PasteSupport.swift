import AppKit

/// What the clipboard holds, as far as pasting into a terminal is concerned.
enum PasteContent: Equatable {
    /// Plain text (or anything else): paste it as the terminal normally would.
    case text
    /// Files copied in Finder: paste their paths.
    case files([URL])
    /// A copied image with no file (a screenshot, "Copy Image" in a browser): PNG data.
    case image(Data)
}

enum PasteResolver {
    /// Files win (a file copied in Finder also carries an icon image); then an
    /// image, but only when there is no text next to it (rich-text apps put a
    /// picture beside the text they copy, and text is what you meant).
    static func resolve(_ pasteboard: NSPasteboard) -> PasteContent {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        let hasText = pasteboard.string(forType: .string).map { !$0.isEmpty } ?? false
        if !hasText, let png = pngData(from: pasteboard) { return .image(png) }
        return .text
    }

    /// The pasteboard's image as PNG (screenshots arrive as TIFF).
    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// Paths as a shell (and Claude/Codex) want to read them: spaces and other
/// special characters escaped with a backslash, like dragging a file onto Terminal.
enum ShellPath {
    private static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./@%+=:,~")

    static func escape(_ path: String) -> String {
        var out = ""
        for character in path {
            // Letters and digits of any language (ação, 写真) need no escape.
            if safe.contains(character) || character.isLetter || character.isNumber { out.append(character) }
            else { out.append("\\"); out.append(character) }
        }
        return out
    }

    /// Several paths, separated by spaces, with a trailing space so the cursor
    /// is ready for the text that follows.
    static func joined(_ paths: [String]) -> String { paths.map(escape).joined(separator: " ") + " " }
}

/// Pasted images are written here, as PNG files, so a tool can be pointed at them.
enum PastedImages {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.axiosnotch.app/Pasted", isDirectory: true)
    }

    /// Writes the image and returns its URL. Also tidies up pictures older than a day.
    static func save(_ png: Data, in directory: URL = PastedImages.directory, now: Date = Date()) -> URL? {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        removeOld(in: directory, now: now)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("axios-paste-\(stamp.string(from: now))-\(UUID().uuidString.prefix(4)).png")
        do { try png.write(to: url, options: .atomic); return url } catch { return nil }
    }

    static func removeOld(in directory: URL, now: Date = Date(), olderThan age: TimeInterval = 24 * 3600) {
        let manager = FileManager.default
        for file in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(modified) > age, file.lastPathComponent.hasPrefix("axios-paste-") { try? manager.removeItem(at: file) }
        }
    }
}
