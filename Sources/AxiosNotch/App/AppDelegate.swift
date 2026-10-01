import AppKit

/// Runs as an accessory app (no Dock icon) — the notch panel is the main UI,
/// but a small menu bar item gives the user a conventional way to pause or
/// quit, since there's no Dock icon to right-click and no normal window to
/// close.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var usageStore: AgentUsageStore?
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var isPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let usageStore = AgentUsageStore()
        self.usageStore = usageStore
        notchController = NotchWindowController(usageStore: usageStore)
        usageStore.start()

        setUpStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageStore?.stop()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let url = Bundle.module.url(forResource: "AxiosMark", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                image.size = NSSize(width: 16, height: 16)
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Axios Notch")
            }
        }

        let menu = NSMenu()

        let pauseItem = NSMenuItem(title: "Pausar", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        pauseMenuItem = pauseItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Sair do Axios Notch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            notchController?.pause()
            usageStore?.stop()
            pauseMenuItem?.title = "Retomar"
        } else {
            notchController?.resume()
            usageStore?.start()
            pauseMenuItem?.title = "Pausar"
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
