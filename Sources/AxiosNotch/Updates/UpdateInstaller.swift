import AppKit
import CryptoKit
import Foundation

enum UpdateError: LocalizedError {
    case notInstalledApp
    case folderNotWritable
    case noDMG
    case missingHash
    case hashMismatch
    case mountFailed
    case wrongApp(String)
    case signatureInvalid
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .notInstalledApp: return tr("Só dá para atualizar o app instalado (.app).", "Only the installed app (.app) can be updated.")
        case .folderNotWritable: return tr("Sem permissão para escrever na pasta do app.", "No permission to write to the app's folder.")
        case .noDMG: return tr("O release não traz um .dmg.", "The release has no .dmg.")
        case .missingHash: return tr("O release não informa o SHA-256; baixe manualmente.", "The release does not list a SHA-256; download it manually.")
        case .hashMismatch: return tr("O arquivo baixado não confere com o SHA-256 do release.", "The downloaded file does not match the release SHA-256.")
        case .mountFailed: return tr("Não foi possível abrir o .dmg.", "Could not open the .dmg.")
        case .wrongApp(let why): return tr("O app do .dmg não é o esperado: \(why).", "The app in the .dmg is not the expected one: \(why).")
        case .signatureInvalid: return tr("A assinatura do app baixado é inválida.", "The downloaded app's signature is invalid.")
        case .copyFailed: return tr("Não foi possível copiar o app novo.", "Could not copy the new app.")
        }
    }
}

enum UpdateInstaller {
    /// Streams the file through SHA-256 so a 20 MB image never sits in memory.
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The script that runs after the app quits: it waits for the process to end,
    /// swaps the bundles with plain renames (same folder, so atomic) and puts the old
    /// one back if anything goes wrong. `relaunch` is `false` in tests.
    static func swapScript(pid: Int32, app: String, staged: String, backup: String, relaunch: Bool) -> String {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let open = relaunch ? "/usr/bin/open \(q(app))" : ":"
        return """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf \(q(backup))
        if mv \(q(app)) \(q(backup)); then
          if mv \(q(staged)) \(q(app)); then
            rm -rf \(q(backup))
          else
            mv \(q(backup)) \(q(app))
            rm -rf \(q(staged))
          fi
        else
          rm -rf \(q(staged))
        fi
        \(open)

        """
    }

    /// Everything except the final quit: downloads, verifies and stages the new app
    /// next to the current one, then returns the script to run once the app has quit.
    static func prepare(_ release: ReleaseInfo, appURL: URL = Bundle.main.bundleURL,
                        expectedIdentifier: String = Bundle.main.bundleIdentifier ?? "com.axiosnotch.app",
                        onInstalling: @escaping @Sendable () -> Void = {}) async throws -> (script: URL, stagedApp: URL) {
        guard appURL.pathExtension == "app" else { throw UpdateError.notInstalledApp }
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateError.folderNotWritable }
        guard let dmgURL = release.dmgURL else { throw UpdateError.noDMG }
        guard let expectedHash = release.sha256 else { throw UpdateError.missingHash }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("axios-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let (tmp, response) = try await URLSession.shared.download(from: dmgURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.noDMG }
        let dmg = work.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: tmp, to: dmg)
        guard try sha256(of: dmg) == expectedHash else { throw UpdateError.hashMismatch }
        onInstalling()

        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path, dmg.path]) == 0 else {
            throw UpdateError.mountFailed
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mount.path]) }

        let apps = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard let newApp = apps.first, apps.count == 1 else { throw UpdateError.wrongApp(tr("não há exatamente um app", "not exactly one app")) }

        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == expectedIdentifier else {
            throw UpdateError.wrongApp(tr("identificador diferente", "different identifier"))
        }
        guard let shown = (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init), shown == release.version else {
            throw UpdateError.wrongApp(tr("versão diferente da do release", "version differs from the release"))
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0 else { throw UpdateError.signatureInvalid }

        let staged = parent.appendingPathComponent(".\(appURL.deletingPathExtension().lastPathComponent).update.app")
        try? FileManager.default.removeItem(at: staged)
        guard run("/usr/bin/ditto", [newApp.path, staged.path]) == 0 else { throw UpdateError.copyFailed }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        let backup = parent.appendingPathComponent(".\(appURL.deletingPathExtension().lastPathComponent).old.app")
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("axios-update-\(UUID().uuidString).sh")
        try swapScript(pid: ProcessInfo.processInfo.processIdentifier, app: appURL.path, staged: staged.path,
                       backup: backup.path, relaunch: true).write(to: script, atomically: true, encoding: .utf8)
        return (script, staged)
    }

    /// Starts the swap script detached from this process, so it survives the quit.
    static func launchScript(_ script: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "nohup /bin/sh '\(script.path)' >/dev/null 2>&1 &"]
        try process.run()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
