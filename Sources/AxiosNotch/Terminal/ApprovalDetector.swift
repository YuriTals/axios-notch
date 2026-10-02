import Foundation

/// Decides, from what is on a terminal's screen, whether Claude Code or Codex
/// has stopped and is waiting for the user: a permission request, a question
/// with options, or a plan to approve.
///
/// Each kind has text that exists only while it is open (so it clears itself
/// once answered):
/// - permission requests end with "No, and tell Claude/Codex what to do differently";
/// - multiple-choice questions end with "Enter to select · ↑/↓ to navigate ·
///   Esc to cancel" (Claude) or "… to navigate questions" (Codex), plus a
///   "Ready to submit your answers?" review step;
/// - plan approval offers "No, keep planning" ("Ready to code?").
enum ApprovalDetector {
    static func needsApproval(lines: [String]) -> Bool {
        let screen = lines.map { $0.lowercased() }
        func any(_ test: (String) -> Bool) -> Bool { screen.contains(where: test) }

        if any({ $0.contains("what to do differently") }) { return true }
        if any({ $0.contains("enter to select") && $0.contains("esc to cancel") }) { return true }
        if any({ $0.contains("to navigate questions") }) { return true }
        if any({ $0.contains("ready to submit your answers") }) { return true }
        if any({ $0.contains("no, keep planning") }) { return true }
        if any({ $0.contains("ready to code?") }) && any({ $0.contains("1.") }) { return true }
        return false
    }

    /// Convenience over a block of text.
    static func needsApproval(text: String) -> Bool {
        needsApproval(lines: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }
}
