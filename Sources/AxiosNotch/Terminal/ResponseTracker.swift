import Foundation

/// Decides when a terminal is "working on a response" and when it finished,
/// from just three signals: the user pressed Enter, output arrived, and time
/// passed. Pure state machine (the caller supplies the clock) so it can be
/// tested without a terminal.
///
/// Two modes, because the two kinds of session look different from outside:
/// - `.silence` (Claude, Codex): the CLI is always the foreground process, but
///   it keeps redrawing its spinner while thinking and goes quiet when done.
///   Working = output flowing; finished = no output for `idleAfter` seconds.
/// - `.foreground` (plain shell): a quiet command like `sleep 60` prints
///   nothing, so silence would be wrong. Working = something other than the
///   shell owns the terminal; finished = the shell has it back.
struct ResponseTracker {
    enum Mode { case silence, foreground }
    enum Event { case finished }

    let mode: Mode
    var idleAfter: TimeInterval = 3
    /// Gives up waiting if nothing ever starts after Enter (an empty line, or
    /// a command that finished before the first poll).
    var giveUpAfter: TimeInterval = 6

    private(set) var isWorking = false
    private var awaiting = false
    private var submittedAt = Date.distantPast
    private var lastOutput = Date.distantPast

    /// True while a poll timer is worth running.
    var needsPolling: Bool { awaiting }

    init(mode: Mode) { self.mode = mode }

    mutating func userSubmitted(now: Date) {
        awaiting = true
        submittedAt = now
        lastOutput = now
    }

    mutating func outputReceived(now: Date) {
        guard awaiting else { return }
        lastOutput = now
        if mode == .silence { isWorking = true }
    }

    /// Call periodically while `needsPolling`. `foregroundBusy` is only read
    /// in `.foreground` mode.
    mutating func tick(now: Date, foregroundBusy: Bool = false) -> Event? {
        guard awaiting else { return nil }
        switch mode {
        case .silence:
            if isWorking {
                if now.timeIntervalSince(lastOutput) >= idleAfter { return finish() }
            } else if now.timeIntervalSince(submittedAt) >= giveUpAfter {
                awaiting = false
            }
        case .foreground:
            if foregroundBusy {
                isWorking = true
            } else if isWorking {
                return finish()
            } else if now.timeIntervalSince(submittedAt) >= 1 {
                awaiting = false
            }
        }
        return nil
    }

    /// The process went away; nothing is pending any more.
    mutating func reset() {
        isWorking = false
        awaiting = false
    }

    private mutating func finish() -> Event {
        isWorking = false
        awaiting = false
        return .finished
    }
}
