import Foundation

/// Short, friendly lines the notch says when something finishes.
enum PhraseBook {
    /// When Claude or Codex has answered.
    static func answer(_ lang: Lang) -> [String] {
        switch lang {
        case .pt:
            return [
                "Ei, vem ver a minha resposta!",
                "Te respondi aqui!",
                "Prontinho, olha só!",
                "Terminei! Vem ver.",
                "Sua resposta chegou!",
                "Acabei por aqui, vem ver!",
            ]
        case .en:
            return [
                "Hey, come see my answer!",
                "Answered you right here!",
                "All done, take a look!",
                "Finished! Come see.",
                "Your answer is here!",
                "Done on my side, come see!",
            ]
        }
    }

    /// When a command in the clean shell is done.
    static func command(_ lang: Lang) -> [String] {
        switch lang {
        case .pt: return ["Terminei por aqui!", "Comando concluído!", "Pronto, já rodou!"]
        case .en: return ["All done here!", "Command finished!", "Done, it ran!"]
        }
    }

    /// When Claude or Codex is stopped, waiting for the user to approve something.
    static func approval(_ lang: Lang) -> [String] {
        switch lang {
        case .pt: return ["Preciso da sua aprovação!", "Posso continuar? Vem ver!", "Estou esperando você aqui!"]
        case .en: return ["I need your approval!", "May I continue? Come see!", "Waiting for you here!"]
        }
    }

    /// Picks a line for an approval request.
    static func pickApproval(avoiding previous: String?, language: Lang = Localization.current,
                             randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let options = approval(language).filter { $0 != previous }
        return options[randomIndex(options.count)]
    }

    /// Picks a line, never the one used last time (when there is a choice).
    static func pick(forShell: Bool, avoiding previous: String?, language: Lang = Localization.current,
                     randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let pool = forShell ? command(language) : answer(language)
        let options = pool.filter { $0 != previous }
        return options[randomIndex(options.count)]
    }
}
