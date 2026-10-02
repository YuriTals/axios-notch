import SwiftUI
import SwiftTerm

/// A terminal view that reports when the user submits a line and when the
/// process prints, which is all `ResponseTracker` needs.
final class ActivityTerminalView: LocalProcessTerminalView {
    var onSubmit: (() -> Void)?
    var onOutput: (() -> Void)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if data.contains(0x0D) { onSubmit?() }
        super.send(source: source, data: data)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }
}

/// Identifies one terminal tab: which tool it runs (`nil` is the clean shell)
/// and its number among that tool's tabs (1, 2, 3…; numbers are not reused
/// while a higher one is open, so a tab's name never changes under you).
struct SessionKey: Hashable {
    let provider: AgentProvider?
    let number: Int

    var providerID: String { provider?.rawValue ?? "shell" }
    var id: String { "\(providerID)#\(number)" }

    /// "Claude 2", "Terminal 1".
    var fallbackTitle: String { "\(provider?.displayName ?? "Terminal") \(number)" }

    static let maxPerProvider = 6
}

/// Keeps every terminal tab alive after its panel closes. SwiftUI destroys a
/// view when its state leaves the screen, which would kill the process and
/// lose the conversation; here each `LocalProcessTerminalView` (and the PTY
/// process behind it) outlives the view and is simply re-attached next time.
/// A tool can have several tabs; a tab whose process exits is dropped.
///
/// It also publishes what each tab is doing for the notch to show: which are
/// alive, which are busy answering, and how many answers finished while nobody
/// was looking at that tab.
final class TerminalSessionStore: ObservableObject {
    static let shared = TerminalSessionStore()

    /// Every open tab, in the order they were opened.
    @Published private(set) var keys: [SessionKey] = []
    /// The tab each tool shows when its panel opens, by provider id.
    @Published private(set) var selection: [String: SessionKey] = [:]
    @Published private(set) var workingIDs: Set<String> = []
    /// Tabs where the tool has stopped to ask for approval.
    @Published private(set) var waitingIDs: Set<String> = []
    /// Finished answers the user has not seen yet, per tab.
    @Published private(set) var unread: [String: Int] = [:]
    /// The most recent unseen finish, for the notch to announce.
    @Published private(set) var lastFinish: NotchNotice?

    /// Folders sessions were used in, for the "+" menu.
    @Published private(set) var recents = RecentProjects.load()

    private var lastPhrase: String?
    /// The tab whose terminal is currently on screen, if any.
    private var visibleKey: SessionKey?
    private var sessions: [SessionKey: Session] = [:]

    // MARK: Queries (aggregated per tool — used by tiles and the closed notch)

    func keys(for provider: AgentProvider?) -> [SessionKey] { keys.filter { $0.provider == provider } }
    func isWaiting(_ provider: AgentProvider?) -> Bool { keys.contains { $0.provider == provider && waitingIDs.contains($0.id) } }
    func isWaiting(_ key: SessionKey) -> Bool { waitingIDs.contains(key.id) }
    var anyWaiting: Bool { !waitingIDs.isEmpty }
    func isActive(_ provider: AgentProvider?) -> Bool { keys.contains { $0.provider == provider } }
    func isWorking(_ provider: AgentProvider?) -> Bool { keys.contains { $0.provider == provider && workingIDs.contains($0.id) } }
    func unreadCount(_ provider: AgentProvider?) -> Int { keys(for: provider).reduce(0) { $0 + (unread[$1.id] ?? 0) } }
    var anyWorking: Bool { !workingIDs.isEmpty }
    var totalUnread: Int { unread.values.reduce(0, +) }

    // MARK: Queries (per tab)

    func selectedKey(for provider: AgentProvider?) -> SessionKey? { selection[provider?.rawValue ?? "shell"] }
    func isWorking(_ key: SessionKey) -> Bool { workingIDs.contains(key.id) }
    func unreadCount(_ key: SessionKey) -> Int { unread[key.id] ?? 0 }

    /// The tab's name: the project folder when it says something, else "Claude 2".
    func title(for key: SessionKey) -> String { sessions[key]?.projectName() ?? key.fallbackTitle }
    func currentDirectory(for key: SessionKey) -> String? { sessions[key]?.currentDirectory() }
    func view(for key: SessionKey) -> LocalProcessTerminalView? { sessions[key]?.view }

    // MARK: Opening, selecting, closing

    /// The tab to show for `provider`: its selected one, creating the first if
    /// the tool has none yet. Call this *before* showing the panel, never from
    /// inside a view update.
    @discardableResult
    func ensureSelected(_ provider: AgentProvider?) -> SessionKey {
        if let key = selectedKey(for: provider), sessions[key] != nil { return key }
        if let first = keys(for: provider).first {
            selection[first.providerID] = first
            return first
        }
        return openSession(provider, directory: nil)
    }

    /// Opens another tab for `provider` and selects it. At the per-tool limit it
    /// just returns the selected tab.
    @discardableResult
    func openSession(_ provider: AgentProvider?, directory: String?) -> SessionKey {
        let existing = keys(for: provider)
        if existing.count >= SessionKey.maxPerProvider { return ensureSelected(provider) }
        let number = (existing.map(\.number).max() ?? 0) + 1
        let key = SessionKey(provider: provider, number: number)

        if let directory { remember(directory) }
        let session = makeSession(for: key, directory: directory)
        sessions[key] = session
        keys.append(key)
        selection[key.providerID] = key
        return key
    }

    func select(_ key: SessionKey) {
        guard sessions[key] != nil else { return }
        selection[key.providerID] = key
    }

    /// Selects a tab by its id ("claude#2"), e.g. from a banner click.
    func select(id: String) {
        if let key = keys.first(where: { $0.id == id }) { select(key) }
    }

    /// Ends a tab's process and removes it; its neighbour takes over.
    func close(_ key: SessionKey) {
        guard let session = sessions[key] else { return }
        if let folder = session.currentDirectory() { remember(folder) }
        session.endProcess()
        remove(key, session: session)
    }

    private func remove(_ key: SessionKey, session: Session) {
        guard sessions[key] === session else { return }
        session.timer?.invalidate()
        session.attentionTimer?.invalidate()
        session.tracker.reset()
        sessions[key] = nil
        let siblings = keys(for: key.provider)
        if let index = siblings.firstIndex(of: key) {
            let remaining = siblings.filter { $0 != key }
            if selection[key.providerID] == key {
                selection[key.providerID] = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
            }
        }
        keys.removeAll { $0 == key }
        workingIDs.remove(key.id)
        waitingIDs.remove(key.id)
        unread[key.id] = nil
        if visibleKey == key { visibleKey = nil }
    }

    // MARK: Recent folders

    private func remember(_ path: String) {
        var updated = recents
        updated.record(path)
        guard updated.paths != recents.paths else { return }
        recents = updated
        updated.save()
    }

    func clearRecents() {
        recents.clear()
        recents.save()
    }

    // MARK: Fonts and visibility

    /// Applies the chosen colour scheme to every live terminal.
    func refreshThemes() {
        let theme = AppSettings.shared.terminalTheme
        for session in sessions.values { theme.apply(to: session.view) }
    }

    /// Applies the current font size to every live terminal.
    func refreshFonts() {
        for session in sessions.values { session.view.font = TerminalFont.resolve() }
    }

    /// A tab's terminal appeared on screen: whatever finished there while away
    /// is now seen.
    func didShow(_ key: SessionKey) {
        visibleKey = key
        DispatchQueue.main.async { [weak self] in self?.unread[key.id] = nil }
    }

    func didHide(view: NSView) {
        guard let key = sessions.first(where: { $0.value.view === view })?.key else { return }
        if visibleKey == key { visibleKey = nil }
    }

    // MARK: Sessions

    private final class Session: LocalProcessTerminalViewDelegate {
        let key: SessionKey
        let view = ActivityTerminalView(frame: .zero)
        var tracker: ResponseTracker
        let mode: ResponseTracker.Mode
        var timer: Timer?
        var attentionTimer: Timer?
        var isWaiting = false
        /// Called when the tool starts or stops asking for approval.
        var onAttention: ((Bool) -> Void)?
        var onExit: (() -> Void)?
        var onChange: (() -> Void)?
        var onFinished: (() -> Void)?

        init(key: SessionKey, mode: ResponseTracker.Mode) {
            self.key = key
            self.mode = mode
            tracker = ResponseTracker(mode: mode)
        }

        func startPolling() {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        }

        private func poll() {
            let busy = mode == .foreground ? foregroundBusy() : false
            let marker = mode == .marker ? screenShowsWorkingMarker() : false
            let wasWorking = tracker.isWorking
            let event = tracker.tick(now: Date(), foregroundBusy: busy, markerVisible: marker)
            if wasWorking != tracker.isWorking || event != nil { onChange?() }
            if event == .finished { onFinished?() }
            if !tracker.needsPolling { timer?.invalidate(); timer = nil }
        }

        /// Is something other than the login shell in the terminal's
        /// foreground? (Only consulted for the clean-shell session.)
        private func foregroundBusy() -> Bool {
            guard let process = view.process, process.running else { return false }
            let group = tcgetpgrp(process.childfd)
            return group > 0 && group != process.shellPid
        }

        /// The visible screen, one string per row.
        private func screenLines() -> [String] {
            let terminal = view.getTerminal()
            return (0..<terminal.rows).map { terminal.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
        }

        /// Codex prints "esc to interrupt" on screen only while it works.
        private func screenShowsWorkingMarker() -> Bool {
            screenLines().contains { $0.localizedCaseInsensitiveContains("esc to interrupt") }
        }

        /// Watches for the tool stopping to ask permission. Cheap (one screen
        /// read a second) and only for Claude/Codex sessions.
        func startWatchingForApproval() {
            guard attentionTimer == nil else { return }
            attentionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                let waiting = ApprovalDetector.needsApproval(lines: self.screenLines())
                guard waiting != self.isWaiting else { return }
                self.isWaiting = waiting
                self.onAttention?(waiting)
            }
        }

        /// Where this session is right now. A shell's own directory is the one
        /// to read (its builtin `cd` changes it); a CLI session keeps the
        /// directory it was started in.
        func currentDirectory() -> String? {
            guard let process = view.process, process.running else { return nil }
            return ProcessDirectory.current(pid: process.shellPid)
        }

        /// The project folder, when it says anything useful.
        func projectName() -> String? {
            currentDirectory().flatMap { ProcessDirectory.projectName(forPath: $0) }
        }

        /// Ends the process the way closing a terminal window does. SwiftTerm's
        /// own `terminate()` sends SIGTERM, which an interactive shell ignores,
        /// so the shell (and anything it started) would be left running.
        func endProcess() {
            guard let process = view.process, process.running else { return }
            let pid = process.shellPid
            view.terminate()
            guard pid > 0 else { return }
            kill(pid, SIGHUP)
            // A process that ignores SIGHUP too gets a moment, then the hard way.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [onExit] in onExit?() }
        }
    }

    private func makeSession(for key: SessionKey, directory: String?) -> Session {
        let mode: ResponseTracker.Mode
        switch key.provider {
        case nil: mode = .foreground
        case .claude: mode = .silence
        case .codex: mode = .marker
        }
        let session = Session(key: key, mode: mode)
        session.view.font = TerminalFont.resolve()
        AppSettings.shared.terminalTheme.apply(to: session.view)
        session.view.processDelegate = session
        session.view.onSubmit = { [weak session] in
            guard let session else { return }
            session.tracker.userSubmitted(now: Date())
            session.startPolling()
        }
        session.view.onOutput = { [weak session] in
            guard let session else { return }
            let wasWorking = session.tracker.isWorking
            session.tracker.outputReceived(now: Date())
            if !wasWorking && session.tracker.isWorking { session.onChange?() }
        }
        session.onChange = { [weak self, weak session] in
            guard let self, let session else { return }
            if session.tracker.isWorking { self.workingIDs.insert(key.id) } else { self.workingIDs.remove(key.id) }
        }
        session.onFinished = { [weak self, weak session] in
            guard let self, self.visibleKey != key else { return }
            // Stopped to ask the user something: the "!" already says so, and
            // calling that an "answer ready" would bury it.
            if session?.isWaiting == true { return }
            if let folder = session?.currentDirectory() { self.remember(folder) }
            self.unread[key.id, default: 0] += 1
            let phrase = PhraseBook.pick(forShell: key.provider == nil, avoiding: self.lastPhrase)
            self.lastPhrase = phrase
            self.lastFinish = NotchNotice(provider: key.provider, project: session?.projectName(), phrase: phrase, sessionID: key.id)
            NoticeSound.playIfEnabled()
        }
        session.onAttention = { [weak self, weak session] waiting in
            guard let self else { return }
            if waiting {
                self.waitingIDs.insert(key.id)
                // Looking at that tab already: nothing to announce.
                guard self.visibleKey != key else { return }
                let phrase = PhraseBook.pickApproval(avoiding: self.lastPhrase)
                self.lastPhrase = phrase
                self.lastFinish = NotchNotice(provider: key.provider, project: session?.projectName(), phrase: phrase,
                                              level: .warning, sessionID: key.id)
                NoticeSound.playIfEnabled()
            } else {
                self.waitingIDs.remove(key.id)
            }
        }
        session.onExit = { [weak self, weak session] in
            guard let self, let session else { return }
            self.remove(key, session: session)
        }
        let (executable, args) = PTYSession.launchArguments(for: key.provider)
        // Start in the home folder unless told otherwise: a packaged .app inherits "/".
        session.view.startProcess(executable: executable, args: args, currentDirectory: directory ?? NSHomeDirectory())
        if mode == .marker { session.startPolling() }
        if key.provider != nil { session.startWatchingForApproval() }
        return session
    }
}
