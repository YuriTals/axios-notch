import Foundation

enum LimitWindow: String, CaseIterable {
    case fiveHour, weekly
}

/// Something worth telling the user about their plan limits.
struct LimitAlert: Equatable {
    enum Kind: Equatable {
        /// Usage crossed 80 or 90 %.
        case threshold(Int)
        /// A window that was running high has started over.
        case reset
    }

    let provider: AgentProvider
    let window: LimitWindow
    let kind: Kind
    let percent: Double

    var message: String {
        let name = provider.displayName
        let phrase: String
        switch window {
        case .fiveHour: phrase = "da janela de 5h"
        case .weekly: phrase = "do limite semanal"
        }
        switch kind {
        case .threshold(let level):
            return "\(name): \(Int(percent.rounded()))% \(phrase)\(level >= 90 ? "!" : "")"
        case .reset:
            return window == .fiveHour ? "\(name): janela de 5h reiniciou!" : "\(name): limite semanal reiniciou!"
        }
    }

    var severity: NotchNotice.Level {
        switch kind {
        case .threshold(let level): return level >= 90 ? .critical : .warning
        case .reset: return .info
        }
    }
}

/// Watches the reported percentages and says when one crosses 80 % or 90 %
/// (once per window), or when a high window starts over. Pure state machine:
/// the caller feeds it every fresh reading.
///
/// The first reading of a window after launch never alerts — you are not
/// told at startup what you already know — it only arms the thresholds.
struct LimitAlertTracker {
    static let thresholds = [80, 90]

    private struct Key: Hashable { let provider: AgentProvider; let window: LimitWindow }
    private struct Seen {
        var resetsAt: Date?
        var level: Int
        var percent: Double
    }
    private var seen: [Key: Seen] = [:]

    /// Same window if the reset time is within this (the API reports it with
    /// sub-second jitter) — and the percentage didn't plunge.
    private static let sameWindowTolerance: TimeInterval = 300
    private static let plungeThreshold = 20.0

    private static func level(for percent: Double) -> Int {
        thresholds.last(where: { percent >= Double($0) }) ?? 0
    }

    mutating func observe(provider: AgentProvider, window: LimitWindow, limit: AgentLimit) -> LimitAlert? {
        let key = Key(provider: provider, window: window)
        let level = Self.level(for: limit.percent)
        guard let previous = seen[key] else {
            seen[key] = Seen(resetsAt: limit.resetsAt, level: level, percent: limit.percent)
            return nil
        }

        let sameWindow: Bool = {
            guard limit.percent >= previous.percent - Self.plungeThreshold else { return false }
            switch (previous.resetsAt, limit.resetsAt) {
            case let (old?, new?): return abs(new.timeIntervalSince(old)) < Self.sameWindowTolerance
            default: return true
            }
        }()

        defer { seen[key] = Seen(resetsAt: limit.resetsAt, level: sameWindow ? max(level, previous.level) : level, percent: limit.percent) }

        if !sameWindow {
            return previous.level > 0
                ? LimitAlert(provider: provider, window: window, kind: .reset, percent: limit.percent)
                : nil
        }
        guard level > previous.level else { return nil }
        return LimitAlert(provider: provider, window: window, kind: .threshold(level), percent: limit.percent)
    }
}
