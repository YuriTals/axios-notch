import XCTest
import SwiftUI
@testable import AxiosNotch

final class CustomToolTests: XCTestCase {
    func testUnicodeInitialCanExpandWithoutCrashing() {
        XCTAssertEqual(CustomTool.initial(for: "ßTool"), "SS")
        XCTAssertEqual(CustomTool.initial(for: "ﬀTool"), "FF")
        XCTAssertEqual(CustomTool.initial(for: "🧑‍💻Tool"), "🧑‍💻")
        XCTAssertEqual(CustomTool.initial(for: "aider"), "A")
        XCTAssertEqual(CustomTool.initial(for: ""), "?")
    }

    private func makeSettings() -> (AppSettings, UserDefaults, String) {
        let suite = "axios-tools-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSettings(defaults: defaults), defaults, suite)
    }

    func testToolIDsRoundTripAndRejectJunk() {
        for tool in [Tool.shell, .agent(.claude), .agent(.codex), .antigravity, .custom("ABC-123")] {
            XCTAssertEqual(Tool(id: tool.id), tool)
        }
        XCTAssertEqual(Tool.custom("x").id, "custom:x")
        XCTAssertEqual(Tool.antigravity.id, "antigravity")
        XCTAssertNil(Tool(id: "wat"))
        XCTAssertNil(Tool(id: "custom:"))
        XCTAssertNil(Tool(id: ""))
        XCTAssertEqual(Tool.agent(.codex).agent, .codex)
        XCTAssertNil(Tool.antigravity.agent, "no usage limits or approval parsing for it")
        XCTAssertNil(Tool.custom("x").agent)
        XCTAssertTrue(Tool.custom("x").isCustom)
        XCTAssertFalse(Tool.antigravity.isCustom, "it is built in, not a registered command")
        XCTAssertTrue(Tool.antigravity.isOtherCLI)
        XCTAssertTrue(Tool.custom("x").isOtherCLI)
        XCTAssertFalse(Tool.agent(.claude).isOtherCLI)
        XCTAssertTrue(Tool.shell.isShell)
    }

    func testTabsSavedByEarlierBuildsReopenAsTheBuiltInAntigravity() {
        // Earlier builds kept it in the custom list, as "custom:gemini" and then "custom:antigravity".
        XCTAssertEqual(Tool(id: "custom:gemini"), .antigravity)
        XCTAssertEqual(Tool(id: "custom:antigravity"), .antigravity)
        XCTAssertEqual(Tool(id: "custom:aider"), .custom("aider"), "other custom tools are untouched")
    }

    func testRegisteringToolsValidatesTrimsAndCaps() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(settings.customTools.isEmpty, "a fresh install has no extra tools")

        XCTAssertFalse(settings.addCustomTool(name: "", command: "aider"))
        XCTAssertFalse(settings.addCustomTool(name: "Aider", command: "   "))
        XCTAssertTrue(settings.addCustomTool(name: "  Aider  ", command: " aider --model sonnet "))
        XCTAssertEqual(settings.customTools.first?.name, "Aider")
        XCTAssertEqual(settings.customTools.first?.command, "aider --model sonnet")

        XCTAssertFalse(settings.addCustomTool(name: "aider", command: "other"), "names are unique, ignoring case")
        for taken in ["Claude", "Codex", "Antigravity", "terminal"] {
            XCTAssertFalse(settings.addCustomTool(name: taken, command: "x"), "must not shadow the built-in tile \(taken)")
        }

        XCTAssertTrue(settings.addCustomTool(name: "Goose", command: "goose"))
        XCTAssertFalse(settings.addCustomTool(name: "Third", command: "x"), "at most \(CustomTool.maxCount) extra tools")
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
        XCTAssertEqual(reopened.customTools.map(\.command), ["aider", "goose session"])

        reopened.removeCustomTool(id: ids[0])
        XCTAssertEqual(AppSettings(defaults: defaults).customTools.map(\.name), ["Goose"])
        reopened.removeCustomTool(id: "does-not-exist")                                   // harmless
        XCTAssertEqual(reopened.customTools.count, 1)

        defaults.set(Data("junk".utf8), forKey: "customTools")
        XCTAssertTrue(AppSettings(defaults: defaults).customTools.isEmpty, "corrupt data must not break launch")
    }

    func testRemovalKeepsToolsAccessibleUntilAllTheirTabsAreClosed() throws {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.addCustomTool(name: "Test", command: "echo test")
        let tool = try XCTUnwrap(settings.customTools.first)
        let sessions = TerminalSessionStore()
        defer { for key in sessions.keys { sessions.close(key) } }
        let first = sessions.openSession(.custom(tool.id), directory: nil)
        let second = sessions.openSession(.custom(tool.id), directory: nil)
        XCTAssertFalse(settings.removeCustomTool(id: tool.id, sessions: sessions))
        XCTAssertNotNil(settings.customToolRemovalError)
        XCTAssertTrue(Tool.all(customTools: settings.customTools).contains(.custom(tool.id)))
        XCTAssertEqual(sessions.keys(for: .custom(tool.id)).count, 2)
        sessions.close(first)
        XCTAssertFalse(settings.removeCustomTool(id: tool.id, sessions: sessions))
        sessions.close(second)
        XCTAssertTrue(settings.removeCustomTool(id: tool.id, sessions: sessions))
        XCTAssertNil(settings.customToolRemovalError)
        XCTAssertTrue(settings.customTools.isEmpty)
    }

    func testAFreshInstallShowsClaudeCodexAntigravityAndTerminal() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Tool.all(customTools: settings.customTools).map { $0.displayName(customTools: settings.customTools) },
                       ["Claude", "Codex", "Antigravity", "Terminal"])
        XCTAssertEqual(Tool.all(customTools: [])[2], .antigravity)
    }

    func testTheToolListIsBuiltInThenExtrasThenTerminal() {
        let mine = [CustomTool(id: "a", name: "Aider", command: "aider")]
        XCTAssertEqual(Tool.all(customTools: mine), [.agent(.claude), .agent(.codex), .antigravity, .custom("a"), .shell])
        XCTAssertEqual(Tool.custom("a").displayName(customTools: mine), "Aider")
        XCTAssertEqual(Tool.custom("gone").displayName(customTools: mine), tr("Ferramenta", "Tool"))
        XCTAssertEqual(Tool.shell.displayName(customTools: mine), "Terminal")
        XCTAssertEqual(Tool.antigravity.displayName(customTools: mine), "Antigravity")
    }

    func testLaunchArgumentsRunTheCommandThroughTheLoginShell() {
        let mine = [CustomTool(id: "a", name: "Aider", command: "aider --model sonnet")]
        let launch = PTYSession.launchArguments(for: .custom("a"), customTools: mine)
        XCTAssertEqual(Array(launch.args.prefix(2)), ["-l", "-c"])
        XCTAssertTrue(launch.args[2].contains("aider --model sonnet"), "the command must run as typed")
        XCTAssertTrue(launch.args[2].hasPrefix("if command -v aider"), "after checking the program exists")
        XCTAssertEqual(PTYSession.launchArguments(for: .custom("removed"), customTools: mine).args, ["-l"], "a removed tool becomes a plain shell")
        XCTAssertEqual(PTYSession.launchArguments(for: .shell, customTools: mine).args, ["-l"])

        let agy = PTYSession.launchArguments(for: .antigravity, customTools: [])
        XCTAssertEqual(Array(agy.args.prefix(2)), ["-l", "-c"])
        XCTAssertTrue(agy.args[2].contains("agy"), agy.args[2])
        XCTAssertTrue(agy.args[2].hasPrefix("if command -v agy"))
    }

    func testEachExtraToolGetsADistinctStableColour() {
        XCTAssertEqual(NotchTheme.customHue(for: "Aider"), NotchTheme.customHue(for: "aider"))
        XCTAssertEqual(NotchTheme.customHue(for: "Aider"), NotchTheme.customHue(for: "Aider"))
        let hues = Set(["Aider", "OpenCode", "Goose", "Cursor"].map(NotchTheme.customHue))
        XCTAssertEqual(hues.count, 4)
        XCTAssertTrue(hues.allSatisfy { (0..<360).contains($0) })
    }

    func testSessionKeysAndTitlesForTheNewTools() {
        let key = SessionKey(tool: .custom("a"), number: 2)
        XCTAssertEqual(key.id, "custom:a#2")
        XCTAssertNil(key.provider)
        XCTAssertEqual(SessionKey(tool: .antigravity, number: 1).id, "antigravity#1")
        XCTAssertEqual(SessionKey(tool: .antigravity, number: 3).fallbackTitle, "Antigravity 3")
        XCTAssertEqual(SessionKey(provider: .claude, number: 1).tool, .agent(.claude))
        XCTAssertEqual(SessionKey(provider: nil, number: 1).tool, .shell)
    }

    func testSavedTabsKeepExtraToolsOnlyWhileTheyExistAndAntigravityAlways() {
        let saved = SavedTabs(tabs: [
            SavedTab(provider: "custom:keep", directory: nil, wasSelected: true),
            SavedTab(provider: "custom:gone", directory: nil, wasSelected: false),
            SavedTab(provider: "antigravity", directory: nil, wasSelected: false),
            SavedTab(provider: "custom:gemini", directory: nil, wasSelected: false),      // an earlier build's Gemini/Antigravity
            SavedTab(provider: "claude", directory: nil, wasSelected: false),
            SavedTab(provider: "wat", directory: nil, wasSelected: false),
            SavedTab(provider: nil, directory: nil, wasSelected: false),
        ])
        let tabs = saved.restorable(customToolIDs: ["keep"], folderExists: { _ in true })
        XCTAssertEqual(tabs.compactMap { $0.provider.flatMap(Tool.init(id:)) },
                       [.custom("keep"), .antigravity, .antigravity, .agent(.claude)])
        XCTAssertEqual(tabs.count, 5, "the plain shell comes back too")
    }

    func testThePickerGrowsToFitMoreTilesButNeverPastTheTerminalWidth() {
        let width = NotchWindowController.pickerWidth(tiles:)
        XCTAssertEqual(width(4), 440, "the default four tiles")
        XCTAssertGreaterThan(width(5), width(4))
        XCTAssertEqual(width(3 + 1 + CustomTool.maxCount), 640, "the full set exactly fills the panel")
        XCTAssertLessThanOrEqual(width(3 + 1 + CustomTool.maxCount), 640, "every tile must fit the window")
    }

    /// A registered tool really runs in a tab: a command that prints and then waits.
    func testAnExtraToolRunsItsCommandInATab() throws {
        let store = TerminalSessionStore()
        defer { for key in store.keys { store.close(key) } }
        // The store reads tools from the shared settings, so register it there for the test and tidy up.
        let before = AppSettings.shared.customTools
        AppSettings.shared.addCustomTool(name: "Eco", command: "echo FERRAMENTA_PERSONALIZADA_OK; sleep 30")
        defer { AppSettings.shared.customTools.map(\.id).filter { id in !before.map(\.id).contains(id) }.forEach { AppSettings.shared.removeCustomTool(id: $0) } }
        let registered = try XCTUnwrap(AppSettings.shared.customTools.first { $0.name == "Eco" })

        let key = store.openSession(.custom(registered.id), directory: nil)
        let started = expectation(description: "command ran"); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { started.fulfill() }
        wait(for: [started], timeout: 5)
        let screen = String(data: try XCTUnwrap(store.view(for: key)).getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
        XCTAssertTrue(screen.contains("FERRAMENTA_PERSONALIZADA_OK"), screen)
        XCTAssertNil(store.lastAnswer(for: key), "no answer copying for tools we cannot read")
    }
}

final class BuiltInAntigravityTests: XCTestCase {
    func testGeminiAndTheOldAntigravityEntryAreDroppedFromSavedLists() {
        let aider = CustomTool(id: "a", name: "Aider", command: "aider")
        let oldGemini = CustomTool(id: "gemini", name: "Gemini", command: "gemini")
        let oldAntigravity = CustomTool(id: "antigravity", name: "Antigravity", command: "agy")
        XCTAssertEqual(CustomTool.migrated([oldGemini, aider, oldAntigravity]), [aider])
        XCTAssertEqual(CustomTool.migrated([]), [])
        // Gemini is discontinued, so even an entry that used custom arguments is removed.
        let edited = CustomTool(id: "gemini", name: "Gemini", command: "gemini --yolo")
        XCTAssertTrue(CustomTool.migrated([edited]).isEmpty)
    }

    func testSettingsSavedByAnEarlierBuildLoseTheirAntigravityAndGeminiEntries() throws {
        let suite = "axios-builtin-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = [CustomTool(id: "antigravity", name: "Antigravity", command: "agy"),
                     CustomTool(id: "a", name: "Aider", command: "aider")]
        defaults.set(try JSONEncoder().encode(saved), forKey: "customTools")
        XCTAssertEqual(AppSettings(defaults: defaults).customTools.map(\.name), ["Aider"])
    }

    func testMigrationIsPersistedAndGeminiTabsBecomeAntigravity() throws {
        let suite = "axios-gemini-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldGemini = CustomTool(id: "gemini", name: "Gemini", command: "gemini --yolo")
        defaults.set(try JSONEncoder().encode([oldGemini]), forKey: "customTools")

        XCTAssertTrue(AppSettings(defaults: defaults).customTools.isEmpty)
        let stored = try XCTUnwrap(defaults.data(forKey: "customTools"))
        XCTAssertTrue(try JSONDecoder().decode([CustomTool].self, from: stored).isEmpty)
        XCTAssertEqual(Tool(id: "custom:gemini"), .antigravity)
    }

    func testGeminiIsNoLongerOfferedAndAntigravityIsNotASuggestion() {
        let names = CustomTool.presets.map(\.name)
        XCTAssertFalse(names.contains("Gemini"), "discontinued")
        XCTAssertFalse(names.contains("Antigravity"), "built in")
        XCTAssertEqual(names, ["Aider", "OpenCode", "Goose"])
        XCTAssertNil(CustomTool.installHint(for: "gemini"), "no install advice for the discontinued CLI")
    }

    func testAntigravityStillExplainsHowToInstallItself() {
        XCTAssertEqual(CustomTool.installHint(for: "agy --continue"), "curl -fsSL https://antigravity.google/cli/install.sh | bash")
        XCTAssertEqual(CustomTool.installHint(for: "goose session"), "brew install block-goose-cli")
        XCTAssertNil(CustomTool.installHint(for: "algo-desconhecido"))
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

    func testAntigravityCarriesItsInstallCommand() {
        let agy = CustomTool(id: "antigravity", name: "Antigravity", command: Tool.antigravityCommand)
        let (output, _) = run(PTYSession.customScript(for: agy, shell: "/bin/echo"))
        // The test environment has no agy on its PATH (/usr/bin:/bin), so the hint is shown.
        XCTAssertTrue(output.contains("curl -fsSL https://antigravity.google/cli/install.sh | bash"), output)
        XCTAssertEqual(CustomTool.installHint(for: "agy --continue"), "curl -fsSL https://antigravity.google/cli/install.sh | bash")
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
