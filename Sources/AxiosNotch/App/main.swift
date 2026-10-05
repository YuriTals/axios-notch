import AppKit

if CommandLine.arguments.contains("--verify-bundle") {
    do {
        try BundleSmokeCheck.run()
        print("Bundle smoke check passed (resources, versions and 12 fonts)")
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Bundle smoke check failed: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

// A plain AppKit entry point. The old SwiftUI `App` only existed to host an
// empty `Settings` scene, which macOS showed as a blank grey "Settings"
// window whenever ⌘, was pressed. Preferences live inside the notch.
let application = NSApplication.shared
private let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
