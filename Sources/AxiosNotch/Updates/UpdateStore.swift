import AppKit
import Foundation

/// Looks for a newer GitHub release and, if the user agrees, installs it.
@MainActor
final class UpdateStore: ObservableObject {
    static let shared = UpdateStore()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case installing
        case failed(String)
    }

    static let repository = "YuriTals/axios-notch"
    private let checkInterval: TimeInterval = 12 * 3600

    @Published private(set) var state: State = .idle
    @Published var automaticChecks: Bool {
        didSet { defaults.set(automaticChecks, forKey: "autoCheckUpdates") }
    }
    @Published private(set) var lastCheck: Date?

    private let defaults: UserDefaults
    private let fetch: () async throws -> Data
    private let currentVersionText: String
    private var timer: Timer?

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
         fetch: (() async throws -> Data)? = nil) {
        self.defaults = defaults
        self.currentVersionText = currentVersion
        self.fetch = fetch ?? {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(UpdateStore.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("AxiosNotch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            return data
        }
        automaticChecks = defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true
        lastCheck = defaults.object(forKey: "lastUpdateCheck") as? Date
    }

    var currentVersion: String { currentVersionText }

    /// Only a real .app can replace itself; `swift run` can look but not install.
    var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var availableRelease: ReleaseInfo? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Checks shortly after launch and then every few hours, if the user allows it.
    func start() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    func checkIfDue(now: Date = Date()) {
        guard automaticChecks, availableRelease == nil else { return }
        if let lastCheck, now.timeIntervalSince(lastCheck) < checkInterval { return }
        Task { await check() }
    }

    func check() async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        do {
            let data = try await fetch()
            lastCheck = Date()
            defaults.set(lastCheck, forKey: "lastUpdateCheck")
            guard let release = ReleaseParser.parse(data) else {
                state = .failed(tr("Resposta inesperada do GitHub.", "Unexpected response from GitHub."))
                return
            }
            if let current = AppVersion(currentVersionText), release.version > current {
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(tr("Sem conexão com o GitHub.", "Could not reach GitHub."))
        }
    }

    /// Downloads, verifies and swaps the app, then quits so the swap script can run.
    func install() async {
        guard case .available(let release) = state else { return }
        state = .downloading
        do {
            let (script, _) = try await UpdateInstaller.prepare(release) { [weak self] in
                Task { @MainActor in self?.state = .installing }
            }
            state = .installing
            // The new app reads this on its first launch and shows what changed.
            WhatsNewStore(defaults: defaults).remember(release)
            try UpdateInstaller.launchScript(script)
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openReleasePage() {
        if let url = availableRelease?.pageURL { NSWorkspace.shared.open(url) }
    }
}
