import AppKit

// A plain AppKit entry point. The old SwiftUI `App` only existed to host an
// empty `Settings` scene, which macOS showed as a blank grey "Settings"
// window whenever ⌘, was pressed. Preferences live inside the notch.
let application = NSApplication.shared
private let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
