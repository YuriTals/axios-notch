import SwiftUI
import SwiftTerm

/// A terminal view that reports when the user submits a line and when the
/// process prints, which is all `ResponseTracker` needs.
private final class ActivityTerminalView: LocalProcessTerminalView {
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

/// An answer that finished while the user was not looking at that terminal.
struct FinishNotice: Equatable {
    /// `nil` is the clean shell.
    let provider: AgentProvider?
    /// Folder the session was working in, when it says anything useful.
    let project: String?
    /// What the notch says about it ("Te respondi aqui!").
    let phrase: String
    let id = UUID()
}

/// Keeps each terminal alive after its panel closes. SwiftUI destroys a
/// view when its state leaves the screen, which would kill the process and
/// lose the conversation; here the `LocalProcessTerminalView` (and the PTY
/// process behind it) outlives the view and is simply re-attached next time.
/// One session per provider, plus one for the clean shell. A session whose
/// process has exited is dropped, so the next open starts fresh.
///
/// It also publishes what each session is doing for the notch to show: which
/// are alive, which are busy answering, and how many answers finished while
/// nobody was looking at that terminal.
final class TerminalSessionStore: ObservableObject {
    static let shared = TerminalSessionStore()

    @Published private(set) var activeKeys: Set<String> = []
    @Published private(set) var workingKeys: Set<String> = []
    /// Finished answers the user has not seen yet, per session.
    @Published private(set) var unread: [String: Int] = [:]
    /// The most recent unseen finish, for the notch to announce.
    @Published private(set) var lastFinish: FinishNotice?

    private var lastPhrase: String?

    /// The session whose terminal is currently on screen, if any.
    private var visibleKey: String?

    static func key(for provider: AgentProvider?) -> String { provider?.rawValue ?? "shell" }

    func isActive(_ provider: AgentProvider?) -> Bool { activeKeys.contains(Self.key(for: provider)) }
    func isWorking(_ provider: AgentProvider?) -> Bool { workingKeys.contains(Self.key(for: provider)) }
    func unreadCount(_ provider: AgentProvider?) -> Int { unread[Self.key(for: provider)] ?? 0 }
    var anyWorking: Bool { !workingKeys.isEmpty }
    var totalUnread: Int { unread.values.reduce(0, +) }

    private final class Session: LocalProcessTerminalViewDelegate {
        let view = ActivityTerminalView(frame: .zero)
        var tracker: ResponseTracker
        let mode: ResponseTracker.Mode
        var timer: Timer?
        var onExit: (() -> Void)?
        var onChange: (() -> Void)?
        var onFinished: (() -> Void)?

        init(mode: ResponseTracker.Mode) {
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

        /// Codex prints "esc to interrupt" on screen only while it works.
        private func screenShowsWorkingMarker() -> Bool {
            let terminal = view.getTerminal()
            for row in 0..<terminal.rows {
                let text = terminal.getLine(row: row)?.translateToString(trimRight: true) ?? ""
                if text.localizedCaseInsensitiveContains("esc to interrupt") { return true }
            }
            return false
        }

        /// The project folder this session is in right now. A shell's own
        /// directory is the one to read (its builtin `cd` changes it); a CLI
        /// session keeps the directory it was started in.
        func projectName() -> String? {
            guard let process = view.process, process.running else { return nil }
            return ProcessDirectory.current(pid: process.shellPid).flatMap { ProcessDirectory.projectName(forPath: $0) }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [onExit] in onExit?() }
        }
    }

    private var sessions: [String: Session] = [:]

    func view(for provider: AgentProvider?) -> LocalProcessTerminalView {
        let key = Self.key(for: provider)
        if let existing = sessions[key] { return existing.view }

        let mode: ResponseTracker.Mode
        switch provider {
        case nil: mode = .foreground
        case .claude: mode = .silence
        case .codex: mode = .marker
        }
        let session = Session(mode: mode)
        session.view.font = TerminalFont.resolve()
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
            self.setWorking(session.tracker.isWorking, key: key)
        }
        session.onFinished = { [weak self, weak session] in
            guard let self, self.visibleKey != key else { return }
            self.unread[key, default: 0] += 1
            let phrase = PhraseBook.pick(forShell: provider == nil, avoiding: self.lastPhrase)
            self.lastPhrase = phrase
            self.lastFinish = FinishNotice(provider: provider, project: session?.projectName(), phrase: phrase)
        }
        session.onExit = { [weak self, weak session] in
            // Only drop it if it is still the current session for this key.
            guard let self, let session, self.sessions[key] === session else { return }
            session.timer?.invalidate()
            session.tracker.reset()
            self.sessions[key] = nil
            self.activeKeys.remove(key)
            self.workingKeys.remove(key)
            self.unread[key] = nil
        }
        let (executable, args) = PTYSession.launchArguments(for: provider)
        // Start in the home folder: a packaged .app inherits "/" as its directory.
        session.view.startProcess(executable: executable, args: args, currentDirectory: NSHomeDirectory())
        if mode == .marker { session.startPolling() }
        sessions[key] = session
        // Created during a SwiftUI update, so publish on the next turn.
        DispatchQueue.main.async { [weak self] in self?.activeKeys.insert(key) }
        return session.view
    }

    /// Applies the current font size to every live terminal.
    func refreshFonts() {
        for session in sessions.values { session.view.font = TerminalFont.resolve() }
    }

    /// The terminal for `provider` appeared on screen: whatever finished
    /// while away is now seen.
    func didShow(_ provider: AgentProvider?) {
        let key = Self.key(for: provider)
        visibleKey = key
        DispatchQueue.main.async { [weak self] in self?.unread[key] = nil }
    }

    func didHide(view: NSView) {
        guard let key = sessions.first(where: { $0.value.view === view })?.key else { return }
        if visibleKey == key { visibleKey = nil }
    }

    private func setWorking(_ working: Bool, key: String) {
        if working { workingKeys.insert(key) } else { workingKeys.remove(key) }
    }
}

/// Bridges SwiftTerm's `LocalProcessTerminalView` (a real VT100 emulator with
/// its own PTY) into SwiftUI. The terminal itself comes from
/// `TerminalSessionStore`, so closing and reopening the panel returns to the
/// same running session.
struct TerminalRepresentable: NSViewRepresentable {
    /// `nil` is the clean shell instead of a provider CLI.
    let provider: AgentProvider?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = TerminalSessionStore.shared.view(for: provider)
        view.removeFromSuperview()
        TerminalSessionStore.shared.didShow(provider)
        return view
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // The provider isn't available here; the store clears by view identity.
        TerminalSessionStore.shared.didHide(view: nsView)
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

/// Prompt themes (Starship, Powerlevel10k…) draw icons from Nerd Font glyph
/// ranges that normal fonts lack, which shows up as "?" boxes. Prefer an
/// installed Nerd Font *Mono* variant (fixed-width glyphs, so columns line
/// up), then any Nerd Font, then the system monospaced font.
enum TerminalFont {
    static var size: CGFloat { CGFloat(AppSettings.shared.terminalFontSize) }
    private static let preferredFamilies = ["FiraCode Nerd Font Mono", "JetBrainsMono Nerd Font Mono", "MesloLGS Nerd Font Mono", "Hack Nerd Font Mono"]

    static func resolve(size: CGFloat = TerminalFont.size) -> NSFont {
        let families = NSFontManager.shared.availableFontFamilies
        let candidates = preferredFamilies
            + families.filter { $0.localizedCaseInsensitiveContains("Nerd Font Mono") }
            + families.filter { $0.localizedCaseInsensitiveContains("Nerd Font") && !$0.localizedCaseInsensitiveContains("Propo") }
        for family in candidates where families.contains(family) {
            if let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

struct TerminalPanelView: View {
    let provider: AgentProvider?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let provider {
                    ProviderGlyph(provider: provider, size: 14)
                } else {
                    TerminalIcon().frame(width: 14, height: 14)
                }
                Text(provider?.displayName ?? "Terminal")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(8)

            TerminalRepresentable(provider: provider)
        }
    }
}
