import Foundation
import ServiceManagement

/// Start-at-login. Inside a real `.app` it uses the system login-item API;
/// when run as a bare SwiftPM binary (no bundle for the system to register)
/// it falls back to a per-user LaunchAgent pointing at this executable.
enum LoginItem {
    static let label = "com.axiosnotch.app"

    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        isBundled ? SMAppService.mainApp.status == .enabled : FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if isBundled {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return
        }
        if enabled {
            let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let data = try launchAgentPlist(executable: executable)
            try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: launchAgentURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    /// Runs at login only; it is not started now, so enabling it never
    /// launches a second copy of the app.
    static func launchAgentPlist(executable: String) throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
