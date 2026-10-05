import AppKit
import Combine

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
    private var settingsMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
    private var languageObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before anything asks for a font: the bundled ones must already exist.
        FontRegistry.registerBundledFonts()

        let usageStore = AgentUsageStore()
        self.usageStore = usageStore
        notchController = NotchWindowController(usageStore: usageStore)
        if AppSettings.shared.reopenTabs { TerminalSessionStore.shared.restoreTabs() }
        TerminalSessionStore.shared.startAutosavingTabs()
        usageStore.start()

        setUpStatusItem()
        UpdateStore.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { WhatsNewWindow.shared.showIfNeeded() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if AppSettings.shared.reopenTabs { TerminalSessionStore.shared.saveTabs() }
        usageStore?.stop()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if BuildChannel.isTest, let url = AppResources.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = false
                button.image = image
                button.toolTip = "Axios Notch — BUILD DE TESTE"
            } else if let url = AppResources.url(forResource: "AxiosMark", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                image.size = NSSize(width: 16, height: 16)
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Axios Notch")
            }
        }

        let menu = NSMenu()
        if BuildChannel.isTest {
            let label = NSMenuItem(title: "⚠ BUILD DE TESTE — Homologação", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: tr("Ajustes…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        settingsMenuItem = settingsItem

        let pauseItem = NSMenuItem(title: tr("Pausar", "Pause"), action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        pauseMenuItem = pauseItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: tr("Sair do Axios Notch", "Quit Axios Notch"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        quitMenuItem = quitItem

        // Re-title the menu the moment the language changes.
        languageObserver = AppSettings.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMenuTitles() }

        item.menu = menu
        statusItem = item
    }

    private func refreshMenuTitles() {
        settingsMenuItem?.title = tr("Ajustes…", "Settings…")
        quitMenuItem?.title = tr("Sair do Axios Notch", "Quit Axios Notch")
        pauseMenuItem?.title = isPaused ? tr("Retomar", "Resume") : tr("Pausar", "Pause")
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            notchController?.pause()
            usageStore?.stop()
            pauseMenuItem?.title = tr("Retomar", "Resume")
        } else {
            notchController?.resume()
            usageStore?.start()
            pauseMenuItem?.title = tr("Pausar", "Pause")
        }
    }

    @objc private func openSettings() {
        // Paused means the panel stays hidden until the user chooses Resume.
        guard !isPaused else { return }
        notchController?.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem !== settingsMenuItem || !isPaused
    }
}
