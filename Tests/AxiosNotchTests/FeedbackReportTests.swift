import XCTest
@testable import AxiosNotch

final class FeedbackReportTests: XCTestCase {
    private let snapshot = FeedbackReport.Snapshot(
        version: "1.0.0", build: "36", macOS: "15.1.0", model: "Mac15,6", language: "Português",
        preferences: [("tema", "gruvbox")], tools: [("claude", "instalado")],
        usage: [("Claude", "ok")], openTabs: 2, customToolCount: 1
    )

    func testDiagnosticsListsVersionsAndStates() {
        let text = FeedbackReport.diagnostics(snapshot)
        XCTAssertTrue(text.contains("Axios Notch 1.0.0 (36)"))
        XCTAssertTrue(text.contains("macOS 15.1.0 · Mac15,6"))
        XCTAssertTrue(text.contains("tema: gruvbox"))
        XCTAssertTrue(text.contains("claude: instalado"))
        XCTAssertTrue(text.contains("ferramentas próprias: 1"))
        XCTAssertTrue(text.contains("Abas abertas: 2"))
    }

    func testMailtoGoesToTheDeveloperAndRoundTripsSpecialCharacters() throws {
        let body = "a&b=c+d\nÉ 100% ok #1"
        let url = try XCTUnwrap(FeedbackReport.mailtoURL(subject: "Axios & Notch", body: body))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:axios.devteam@gmail.com?"))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "subject" }?.value, "Axios & Notch")
        XCTAssertEqual(query.first { $0.name == "body" }?.value, body)
    }

    func testInstalledCheckLooksOnlyInTheUsualFolders() throws {
        let home = NSTemporaryDirectory() + "feedback-\(UUID().uuidString)"
        let bin = home + "/.local/bin"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let tool = bin + "/zz-axios-fake"
        FileManager.default.createFile(atPath: tool, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertTrue(FeedbackReport.isInstalled("zz-axios-fake", home: home))
        XCTAssertFalse(FeedbackReport.isInstalled("zz-axios-missing", home: home))
    }

    @MainActor
    func testSnapshotNeverContainsPathsOrCustomCommands() {
        let text = FeedbackReport.diagnostics(
            FeedbackReport.snapshot(settings: .shared, usage: AgentUsageStore(), sessions: .shared)
        )
        XCTAssertFalse(text.contains(NSHomeDirectory()))
        XCTAssertFalse(text.contains("/Users/"))
    }
}
