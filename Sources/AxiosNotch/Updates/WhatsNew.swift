import AppKit
import SwiftUI

/// "What's new" after an update: the app that installs a release remembers its
/// notes, and the new app shows them once, in a small window, on its first launch.
struct WhatsNewStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    struct Entry: Equatable {
        let version: AppVersion
        let notes: String
    }

    /// Called by the old app right before it installs the new one.
    func remember(_ release: ReleaseInfo) {
        defaults.set(release.version.description, forKey: "pendingWhatsNewVersion")
        defaults.set(release.notes, forKey: "pendingWhatsNewNotes")
    }

    /// The notes to show now, if this launch is the first one after an update. Reading
    /// them clears them, so the window never appears twice.
    func consume(currentVersion: String) -> Entry? {
        guard let current = AppVersion(currentVersion) else { return nil }
        defer {
            defaults.removeObject(forKey: "pendingWhatsNewVersion")
            defaults.removeObject(forKey: "pendingWhatsNewNotes")
            defaults.set(current.description, forKey: "lastRunVersion")
        }
        guard let pending = defaults.string(forKey: "pendingWhatsNewVersion").flatMap(AppVersion.init),
              pending == current else { return nil }
        let notes = Self.clean(Self.section(of: defaults.string(forKey: "pendingWhatsNewNotes") ?? "", for: Localization.current))
        return notes.isEmpty ? nil : Entry(version: current, notes: notes)
    }

    /// Releases carry both languages, each under a `<!-- en -->` or `<!-- pt-BR -->`
    /// marker (invisible on GitHub). The app shows the user's language, and falls back
    /// to the first one present; notes without markers are used as they are.
    static func section(of notes: String, for language: Lang) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<!--\\s*(en|pt-br)\\s*-->", options: .caseInsensitive) else { return notes }
        let text = notes as NSString
        let matches = regex.matches(in: notes, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return notes }
        var sections: [(lang: Lang, text: String)] = []
        for (i, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : text.length
            let tag = text.substring(with: match.range(at: 1)).lowercased()
            sections.append((tag == "en" ? .en : .pt, text.substring(with: NSRange(location: start, length: end - start))))
        }
        return (sections.first { $0.lang == language } ?? sections[0]).text
    }

    /// Keeps only what changed: the headline sections, without the install,
    /// requirements and checksum boilerplate every release carries at the bottom.
    static func clean(_ notes: String) -> String {
        let boilerplate = ["**install", "**instalar", "**requirements", "**requisitos", "sha-256"]
        var kept: [String] = []
        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if boilerplate.contains(where: { lower.hasPrefix($0) }) { break }
            if trimmed.hasPrefix("#") { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class WhatsNewWindow {
    static let shared = WhatsNewWindow()
    private var window: NSWindow?

    /// Shows the window for this launch, if an update just happened.
    func showIfNeeded(store: WhatsNewStore = WhatsNewStore(),
                      currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
        guard let entry = store.consume(currentVersion: currentVersion) else { return }
        show(entry)
    }

    func show(_ entry: WhatsNewStore.Entry) {
        let view = WhatsNewView(version: entry.version.description, notes: entry.notes) { [weak self] in
            self?.window?.close()
        }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = tr("Novidades", "What's new")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 330))
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct WhatsNewView: View {
    let version: String
    let notes: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let url = AppResources.url(forResource: "AxiosMark", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Axios Notch atualizado", "Axios Notch updated")).font(.headline)
                    Text(tr("Versão \(version)", "Version \(version)")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(rendered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(tr("Ok", "OK"), action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 330)
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(notes)
    }
}
