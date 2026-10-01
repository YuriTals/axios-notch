import AppKit

/// Runs as an accessory app (no Dock icon, no menu bar menu) — the notch
/// panel itself is the entire UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var usageStore: AgentUsageStore?
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let usageStore = AgentUsageStore()
        self.usageStore = usageStore
        notchController = NotchWindowController(usageStore: usageStore)
        usageStore.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageStore?.stop()
    }
}
