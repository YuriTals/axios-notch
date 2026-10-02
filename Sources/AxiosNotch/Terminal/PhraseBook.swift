import Foundation

/// Short, friendly lines the notch says when something finishes.
enum PhraseBook {
    /// When Claude or Codex has answered.
    static let answer = [
        "Ei, vem ver a minha resposta!",
        "Te respondi aqui!",
        "Prontinho, olha só!",
        "Terminei! Vem ver.",
        "Sua resposta chegou!",
        "Acabei por aqui, vem ver!",
    ]

    /// When a command in the clean shell is done.
    static let command = [
        "Terminei por aqui!",
        "Comando concluído!",
        "Pronto, já rodou!",
    ]

    /// Picks a line, never the one used last time (when there is a choice).
    static func pick(forShell: Bool, avoiding previous: String?, randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let pool = forShell ? command : answer
        let options = pool.filter { $0 != previous }
        return options[randomIndex(options.count)]
    }
}
