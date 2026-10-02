import AppKit
import UniformTypeIdentifiers

/// Decides what the notch does while the user drags files across the screen.
/// Pure rules (the caller supplies the geometry), so they can be tested.
enum FileDragRules {
    enum Action: Equatable { case none, open, close }

    /// How close to the notch a drag has to get to wake it up.
    static let triggerHalfWidth: CGFloat = 170
    static let triggerDepth: CGFloat = 70
    /// How far outside the open surface the pointer may wander before it closes.
    static let leaveMargin: CGFloat = 50

    /// The strip of screen just around the notch that wakes it up (AppKit
    /// coordinates: origin bottom-left, so the top edge is `notch.maxY`).
    static func triggerZone(notch: CGRect) -> CGRect {
        CGRect(x: notch.midX - triggerHalfWidth, y: notch.maxY - triggerDepth, width: triggerHalfWidth * 2, height: triggerDepth + 20)
    }

    static func action(isFileDrag: Bool, pointer: CGPoint, notch: CGRect, openSurface: CGRect?, isDropOpen: Bool, isIdle: Bool) -> Action {
        guard isFileDrag else { return isDropOpen ? .close : .none }
        if isDropOpen {
            // Already showing the targets: stay while the pointer is on or near them.
            guard let surface = openSurface else { return .close }
            return surface.insetBy(dx: -leaveMargin, dy: -leaveMargin).contains(pointer) ? .none : .close
        }
        // Only wake from rest: an open picker/terminal/settings is not interrupted.
        return isIdle && triggerZone(notch: notch).contains(pointer) ? .open : .none
    }
}

enum FileDrag {
    /// The files being dragged right now, from the system's drag pasteboard.
    static func currentFileURLs() -> [URL] {
        fileURLs(in: NSPasteboard(name: .drag))
    }

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    /// Reads the file URLs out of what a SwiftUI drop hands over.
    static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let identifier = UTType.fileURL.identifier
        let lock = NSLock()
        var found: [(Int, URL)] = []
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() where provider.hasItemConformingToTypeIdentifier(identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let direct = item as? URL { url = direct }
                if let url { lock.lock(); found.append((index, url)); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(found.sorted { $0.0 < $1.0 }.map(\.1)) }
    }
}
