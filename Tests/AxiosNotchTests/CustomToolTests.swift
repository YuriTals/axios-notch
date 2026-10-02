import XCTest
import SwiftUI
@testable import AxiosNotch

final class CustomToolTests: XCTestCase {
    private func makeSettings() -> (AppSettings, UserDefaults, String) {
        let suite = "axios-tools-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSettings(defaults: defaults), defaults, suite)
    }

    func testToolIDsRoundTripAndRejectJunk() {
        for tool in [Tool.shell, .agent(.claude), .agent(.codex), .custom("ABC-123")] {
            XCTAssertEqual(Tool(id: tool.id), tool)
        }
        XCTAssertEqual(Tool.custom("x").id, "custom:x")
        XCTAssertNil(Tool(id: "wat"))
        XCTAssertNil(Tool(id: "custom:"))
        XCTAssertNil(Tool(id: ""))
        XCTAssertEqual(Tool.agent(.codex).agent, .codex)
        XCTAssertNil(Tool.custom("x").agent)
        XCTAssertTrue(Tool.custom("x").isCustom)
        XCTAssertTrue(Tool.shell.isShell)
    }

    func testRegisteringToolsValidatesTrimsAndCaps() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.removeCustomTool(id: CustomTool.antigravityID)                         // start from an empty list
        XCTAssertFalse(settings.addCustomTool(name: "", command: "agy"))
        XCTAssertFalse(settings.addCustomTool(name: "Antigravity", command: "   "))
        XCTAssertTrue(settings.addCustomTool(name: "  Antigravity  ", command: " agy --continue "))
        XCTAssertEqual(settings.customTools.first?.name, "Antigravity")
        XCTAssertEqual(settings.customTools.first?.command, "agy --continue")

        XCTAssertFalse(settings.addCustomTool(name: "antigravity", command: "other"), "names are unique, ignoring case")
        XCTAssertFalse(settings.addCustomTool(name: "Claude", command: "x"), "must not shadow a built-in tile")
        XCTAssertFalse(settings.addCustomTool(name: "terminal", command: "x"))

        XCTAssertTrue(settings.addCustomTool(name: "Aider", command: "aider"))
        XCTAssertTrue(settings.addCustomTool(name: "Goose", command: "goose"))
        XCTAssertFalse(settings.addCustomTool(name: "Fourth", command: "x"), "at most \(CustomTool.maxCount) tools")
        XCTAssertEqual(settings.customTools.count, CustomTool.maxCount)

        XCTAssertEqual(CustomTool(name: String(repeating: "m", count: 40), command: "x").normalized().name.count, CustomTool.maxNameLength)
    }

    func testToolsPersistAndCanBeRemoved() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.addCustomTool(name: "Aider", command: "aider")
        settings.addCustomTool(name: "Goose", command: "goose session")
        let ids = settings.customTools.map(\.id)

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.customTools.map(\.id), ids)
        XCTAssertEqual(reopened.customTools.map(\.command), ["agy", "aider", "goose session"])

        reopened.removeCustomTool(id: ids[1])
        XCTAssertEqual(AppSettings(defaults: defaults).customTools.map(\.name), ["Antigravity", "Goose"])
        reopened.removeCustomTool(id: "does-not-exist")                                   // harmless
        XCTAssertEqual(reopened.customTools.count, 2)

        defaults.set(Data("junk".utf8), forKey: "customTools")
        XCTAssertEqual(AppSettings(defaults: defaults).customTools, CustomTool.defaults, "corrupt data falls back to the standard set")
    }

    func testAFreshInstallStartsWithClaudeCodexAntigravityAndTerminal() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(settings.customTools.map(\.name), ["Antigravity"])
        XCTAssertEqual(settings.customTools.map(\.command), ["agy"])
        XCTAssertEqual(Tool.all(customTools: settings.customTools).map { $0.displayName(customTools: settings.customTools) },
                       ["Claude", "Codex", "Antigravity", "Terminal"])
        XCTAssertEqual(Tool.all(customTools: settings.customTools)[2], .custom(CustomTool.antigravityID))
    }

    func testRemovingTheDefaultIsRespectedAndNotBroughtBack() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.removeCustomTool(id: CustomTool.antigravityID)
        XCTAssertTrue(settings.customTools.isEmpty)
        XCTAssertTrue(AppSettings(defaults: defaults).customTools.isEmpty, "an empty list the user chose must stay empty")
        XCTAssertTrue(AppSettings(defaults: defaults).addCustomTool(name: "Antigravity", command: "agy"), "and it can be added again")
    }

    func testTheToolListIsBuiltInThenCustomThenTerminal() {
        let mine = [CustomTool(id: "a", name: "Aider", command: "aider")]
        XCTAssertEqual(Tool.all(customTools: mine), [.agent(.claude), .agent(.codex), .custom("a"), .shell])
        XCTAssertEqual(Tool.all(customTools: []), [.agent(.claude), .agent(.codex), .shell])
        XCTAssertEqual(Tool.custom("a").displayName(customTools: mine), "Aider")
        XCTAssertEqual(Tool.custom("gone").displayName(customTools: mine), tr("Ferramenta", "Tool"))
        XCTAssertEqual(Tool.shell.displayName(customTools: mine), "Terminal")
    }

    func testLaunchArgumentsRunTheUsersCommandThroughTheLoginShell() {
        let mine = [CustomTool(id: "a", name: "Aider", command: "aider --model sonnet")]
        let launch = PTYSession.launchArguments(for: .custom("a"), customTools: mine)
        XCTAssertEqual(Array(launch.args.prefix(2)), ["-l", "-c"])
        XCTAssertTrue(launch.args[2].contains("aider --model sonnet"), "the command must run as typed")
        XCTAssertTrue(launch.args[2].hasPrefix("if command -v aider"), "after checking the program exists")
        XCTAssertEqual(PTYSession.launchArguments(for: .custom("removed"), customTools: mine).args, ["-l"], "a removed tool becomes a plain shell")
        XCTAssertEqual(PTYSession.launchArguments(for: .shell, customTools: mine).args, ["-l"])
    }

    func testEachToolGetsADistinctStableColour() {
        XCTAssertEqual(NotchTheme.customHue(for: "Aider"), NotchTheme.customHue(for: "aider"))
        XCTAssertEqual(NotchTheme.customHue(for: "Aider"), NotchTheme.customHue(for: "Aider"))
        let hues = Set(["Antigravity", "Aider", "OpenCode", "Goose"].map(NotchTheme.customHue))
        XCTAssertEqual(hues.count, 4)
        XCTAssertTrue(hues.allSatisfy { (0..<360).contains($0) })
    }

    func testSessionKeysAndTitlesForACustomTool() {
        let key = SessionKey(tool: .custom("a"), number: 2)
        XCTAssertEqual(key.id, "custom:a#2")
        XCTAssertNil(key.provider)
        XCTAssertEqual(SessionKey(provider: .claude, number: 1).tool, .agent(.claude))
        XCTAssertEqual(SessionKey(provider: nil, number: 1).tool, .shell)
    }

    func testSavedTabsKeepCustomToolsOnlyWhileTheyStillExist() {
        let saved = SavedTabs(tabs: [
            SavedTab(provider: "custom:keep", directory: nil, wasSelected: true),
            SavedTab(provider: "custom:gone", directory: nil, wasSelected: false),
            SavedTab(provider: "claude", directory: nil, wasSelected: false),
            SavedTab(provider: "wat", directory: nil, wasSelected: false),
            SavedTab(provider: nil, directory: nil, wasSelected: false),
        ])
        let tabs = saved.restorable(customToolIDs: ["keep"], folderExists: { _ in true })
        XCTAssertEqual(tabs.map(\.provider), ["custom:keep", "claude", nil])
    }

    func testThePickerGrowsToFitMoreTilesButNeverPastTheTerminalWidth() {
        let controller = NotchWindowController.pickerWidth(tiles:)
        XCTAssertEqual(controller(3), 340)
        XCTAssertEqual(controller(4), 440, "the default four tiles")
        XCTAssertGreaterThan(controller(5), controller(4))
        XCTAssertLessThanOrEqual(controller(2 + CustomTool.maxCount + 1), 640, "every tile must fit the window")
    }

    /// A custom tool really runs in a tab: a command that prints and then waits.
    func testACustomToolRunsItsCommandInATab() throws {
        let store = TerminalSessionStore()
        defer { for key in store.keys { store.close(key) } }
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = settings
        let tool = CustomTool(id: "t-\(UUID().uuidString.prefix(6))", name: "Eco", command: "echo FERRAMENTA_PERSONALIZADA_OK; sleep 30")
        // The store reads tools from the shared settings, so register it there for the test and tidy up.
        let before = AppSettings.shared.customTools
        AppSettings.shared.addCustomTool(name: tool.name, command: tool.command)
        defer { AppSettings.shared.customTools.map(\.id).filter { id in !before.map(\.id).contains(id) }.forEach { AppSettings.shared.removeCustomTool(id: $0) } }
        let registered = try XCTUnwrap(AppSettings.shared.customTools.first { $0.name == "Eco" })

        let key = store.openSession(.custom(registered.id), directory: nil)
        _ = AppSettings.shared.customTools.count
        let started = expectation(description: "command ran"); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { started.fulfill() }
        wait(for: [started], timeout: 5)
        let screen = String(data: try XCTUnwrap(store.view(for: key)).getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(screen.contains("FERRAMENTA_PERSONALIZADA_OK"), screen)
        XCTAssertEqual(store.title(for: key).isEmpty, false)
        XCTAssertNil(store.lastAnswer(for: key), "no answer copying for tools we cannot read")
    }
}


final class CustomToolLaunchTests: XCTestCase {
    private func run(_ script: String, environment: [String: String] = ["PATH": "/usr/bin:/bin"]) -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.environment = environment
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try? process.run(); process.waitUntilExit()
        return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "", process.terminationStatus)
    }

    func testAnInstalledProgramJustRuns() {
        let tool = CustomTool(id: "t", name: "Eco", command: "echo funcionando")
        let (output, status) = run(PTYSession.customScript(for: tool))
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "funcionando")
        XCTAssertEqual(status, 0)
    }

    func testAMissingProgramExplainsHowToInstallAndKeepsAShell() {
        let tool = CustomTool(id: "antigravity", name: "Antigravity", command: "agy-nao-existe-xyz")
        let (output, _) = run(PTYSession.customScript(for: tool, shell: "/bin/echo"))           // hands over to `echo -l`
        XCTAssertTrue(output.contains("Antigravity"), output)
        XCTAssertTrue(output.contains(tr("não está instalado", "isn't installed")), output)
        XCTAssertTrue(output.contains("-l"), "it must hand over to a login shell instead of exiting: \(output)")
    }

    /// The bug that made the Antigravity tile close itself: an app opened from the Finder has
    /// no SHELL, so a script that relied on it died instead of leaving a shell open.
    func testTheFallbackDoesNotDependOnTheShellVariable() {
        let tool = CustomTool(id: "antigravity", name: "Antigravity", command: "agy-nao-existe-xyz")
        let (output, status) = run(PTYSession.customScript(for: tool, shell: "/bin/echo"), environment: ["PATH": "/usr/bin:/bin"])   // no SHELL at all
        XCTAssertFalse(output.contains("permission denied"), output)
        XCTAssertFalse(output.contains("not found"), output)
        XCTAssertTrue(output.contains("-l"), "must reach the hand-over: \(output)")
        XCTAssertEqual(status, 0)
        XCTAssertEqual(PTYSession.loginShell(environment: [:]), "/bin/zsh")
        XCTAssertEqual(PTYSession.loginShell(environment: ["SHELL": ""]), "/bin/zsh")
        XCTAssertEqual(PTYSession.loginShell(environment: ["SHELL": "/bin/bash"]), "/bin/bash")
    }

    func testTheAntigravityDefaultCarriesItsInstallCommand() {
        let (output, _) = run(PTYSession.customScript(for: CustomTool.defaultAntigravity, shell: "/bin/echo"))
        // The test environment has no agy on its PATH (/usr/bin:/bin), so the hint is shown.
        XCTAssertTrue(output.contains("curl -fsSL https://antigravity.google/cli/install.sh | bash"), output)
        XCTAssertEqual(CustomTool.installHint(for: "agy --continue"), "curl -fsSL https://antigravity.google/cli/install.sh | bash")
        XCTAssertEqual(CustomTool.installHint(for: "gemini"), "npm install -g @google/gemini-cli", "the old CLI is still a suggestion")
        XCTAssertEqual(CustomTool.installHint(for: "goose session"), "brew install block-goose-cli")
        XCTAssertNil(CustomTool.installHint(for: "algo-desconhecido"))
    }

    func testCommandsWithShellSyntaxRunExactlyAsTyped() {
        // Whole command is the user's: it must behave exactly as if typed in a terminal.
        let cases: [(command: String, expected: String)] = [
            ("echo a; echo b", "a\nb"),
            ("echo oi | tr a-z A-Z", "OI"),
            ("FOO=1 env | grep ^FOO", "FOO=1"),
            ("echo \"com aspas\"", "com aspas"),
        ]
        for (command, expected) in cases {
            let tool = CustomTool(id: "t", name: "X", command: command)
            let (output, status) = run(PTYSession.customScript(for: tool))
            XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), expected, command)
            XCTAssertEqual(status, 0, command)
        }
        // A first word with a variable assignment is not a program name: left untouched.
        XCTAssertEqual(PTYSession.customScript(for: CustomTool(id: "t", name: "X", command: "FOO=1 env | grep FOO")), "FOO=1 env | grep FOO")
        XCTAssertTrue(CustomTool.isPlainProgram("agy"))
        XCTAssertTrue(CustomTool.isPlainProgram("/opt/homebrew/bin/opencode"))
        XCTAssertFalse(CustomTool.isPlainProgram("a;b"))
        XCTAssertFalse(CustomTool.isPlainProgram(""))
    }

    func testANameWithAQuoteCannotBreakTheMessage() {
        let tool = CustomTool(id: "t", name: "Don't", command: "nao-existe-abc")
        let (output, _) = run(PTYSession.customScript(for: tool, shell: "/bin/echo"))
        XCTAssertTrue(output.contains("Don't"), output)
    }
}


final class GeminiMigrationTests: XCTestCase {
    func testTheUntouchedGeminiDefaultBecomesAntigravityInPlace() {
        let aider = CustomTool(id: "a", name: "Aider", command: "aider")
        let migrated = CustomTool.migrated([aider, CustomTool.legacyGemini])
        XCTAssertEqual(migrated.map(\.id), ["a", CustomTool.antigravityID])
        XCTAssertEqual(migrated.last?.command, "agy")
    }

    func testAnEditedGeminiIsLeftAloneAndNothingIsDuplicated() {
        let edited = CustomTool(id: "gemini", name: "Gemini", command: "gemini --yolo")
        XCTAssertEqual(CustomTool.migrated([edited]), [edited])
        XCTAssertEqual(CustomTool.migrated([]), [])
        XCTAssertEqual(CustomTool.migrated([CustomTool.defaultAntigravity]), [CustomTool.defaultAntigravity])
        // Both present: keep Antigravity, drop the stale default.
        XCTAssertEqual(CustomTool.migrated([CustomTool.legacyGemini, CustomTool.defaultAntigravity]), [CustomTool.defaultAntigravity])
    }

    func testSettingsSavedByAnOlderVersionComeBackAsAntigravity() throws {
        let suite = "axios-gemini-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([CustomTool.legacyGemini]), forKey: "customTools")
        XCTAssertEqual(AppSettings(defaults: defaults).customTools, [CustomTool.defaultAntigravity])
    }

    func testSavedGeminiTabsReopenAsAntigravityButOnlyAfterTheMigration() {
        XCTAssertEqual(CustomTool.migratedID("gemini", in: [CustomTool.defaultAntigravity]), "antigravity")
        XCTAssertEqual(CustomTool.migratedID("gemini", in: [CustomTool.legacyGemini]), "gemini", "an edited, still-present Gemini keeps its tabs")
        XCTAssertEqual(CustomTool.migratedID("aider", in: [CustomTool.defaultAntigravity]), "aider")
    }
}

@MainActor
final class AntigravityMarkTests: XCTestCase {
    private func render(_ size: CGFloat = 256) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: AntigravityMark().frame(width: size, height: size))
        renderer.scale = 1
        guard let image: NSImage = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { throw XCTSkip("could not render the mark") }
        if let dir = ProcessInfo.processInfo.environment["AXIOS_RENDER_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("antigravity-\(Int(size)).png"))
        }
        return rep
    }

    /// Colour at a point given in the artwork's own 768 × 768 coordinates.
    private func color(_ rep: NSBitmapImageRep, _ x: Double, _ y: Double, canvas: Double = 256) -> (r: Double, g: Double, b: Double, a: Double) {
        let b = AntigravityMark.bounds
        let width = b.maxX - b.minX, height = b.maxY - b.minY
        let scale = canvas / max(width, height)
        let ox = (canvas - width * scale) / 2, oy = (canvas - height * scale) / 2
        let px = Int(ox + (x - b.minX) * scale), py = Int(oy + (y - b.minY) * scale)
        let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB)
        return (Double(c?.redComponent ?? 0), Double(c?.greenComponent ?? 0), Double(c?.blueComponent ?? 0), Double(c?.alphaComponent ?? 0))
    }

    func testTheOutlineIsTheArtworkSilhouette() {
        let pts = AntigravityMark.outline
        let xs: [Double] = pts.map { $0.x }, ys: [Double] = pts.map { $0.y }
        XCTAssertEqual(xs.min()!, AntigravityMark.bounds.minX, accuracy: 3)
        XCTAssertEqual(xs.max()!, AntigravityMark.bounds.maxX, accuracy: 3)
        XCTAssertEqual(ys.min()!, AntigravityMark.bounds.minY, accuracy: 3)
        XCTAssertEqual(ys.max()!, AntigravityMark.bounds.maxY, accuracy: 3)
        XCTAssertTrue(pts.allSatisfy { (0...768).contains($0.x) && (0...768).contains($0.y) })
        XCTAssertEqual(pts.min { $0.y < $1.y }!.x, 384, accuracy: 10, "the peak is centred")
    }

    func testTheArchIsSolidAroundTheEdgesAndHollowUnderneath() throws {
        let rep = try render()
        XCTAssertGreaterThan(color(rep, 384, 160).a, 0.95, "solid near the peak")
        XCTAssertGreaterThan(color(rep, 235, 400).a, 0.95, "solid on the left leg")
        XCTAssertGreaterThan(color(rep, 540, 400).a, 0.95, "solid on the right leg")
        XCTAssertLessThan(color(rep, 384, 520).a, 0.05, "the space under the arch is empty")
        XCTAssertLessThan(color(rep, 384, 600).a, 0.05)
        XCTAssertLessThan(color(rep, 60, 60).a, 0.05, "and so is everything outside it")
        XCTAssertLessThan(color(rep, 700, 650).a, 0.05)
    }

    func testTheColoursMatchTheArtwork() throws {
        let rep = try render()
        let topLeft = color(rep, 300, 200), topRight = color(rep, 470, 190), low = color(rep, 250, 470), lowRight = color(rep, 560, 470)
        XCTAssertGreaterThan(topLeft.g, topLeft.b, "green at the upper left")
        XCTAssertGreaterThan(topLeft.g, topLeft.r - 0.05)
        XCTAssertGreaterThan(topRight.r, topRight.b, "red at the upper right")
        XCTAssertGreaterThan(topRight.r, topRight.g)
        XCTAssertGreaterThan(low.b, low.r + 0.2, "blue lower down")
        XCTAssertGreaterThan(lowRight.b, lowRight.r + 0.2)
    }

    func testTheFeetFadeTowardTheirTips() throws {
        let rep = try render()
        let upper = color(rep, 195, 500), tip = color(rep, 135, 612)
        XCTAssertGreaterThan(upper.a, 0.95)
        XCTAssertLessThan(tip.a, upper.a - 0.2, "the tip is see-through")
        XCTAssertGreaterThan(tip.a, 0.15, "but not gone")
    }
}
