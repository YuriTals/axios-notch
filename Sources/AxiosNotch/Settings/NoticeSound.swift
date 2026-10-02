import AppKit

/// The system sounds offered for "answer ready" / "waiting for you".
enum SoundChoice: String, CaseIterable, Identifiable {
    case glass, ping, pop, tink, hero, purr

    var id: String { rawValue }

    /// The name macOS knows the sound by (files in /System/Library/Sounds).
    var systemName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var label: String { systemName }
}

/// Plays the chosen sound when a session announces something.
enum NoticeSound {
    @discardableResult
    static func play(_ choice: SoundChoice) -> NSSound? {
        guard let sound = NSSound(named: NSSound.Name(choice.systemName)) else { return nil }
        sound.stop()               // a second notice restarts it instead of piling up
        sound.play()
        return sound
    }

    /// Plays it only if the user turned sound on.
    static func playIfEnabled(settings: AppSettings = .shared) {
        guard settings.soundOnNotice else { return }
        play(settings.soundChoice)
    }
}
