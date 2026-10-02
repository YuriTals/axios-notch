import XCTest
@testable import AxiosNotch

final class SystemNotifierTests: XCTestCase {
    func testContentNamesTheToolAndJoinsProjectAndPhrase() {
        let notice = NotchNotice(tool: .agent(.claude), project: "Axios Notch", phrase: "Te respondi aqui!")
        let text = SystemNotifier.content(for: notice, customTools: [])
        XCTAssertEqual(text.title, "Claude")
        XCTAssertEqual(text.body, "Axios Notch · Te respondi aqui!")
    }

    func testContentWithoutProjectIsJustThePhrase() {
        let notice = NotchNotice(tool: .shell, project: nil, phrase: "Pronto")
        XCTAssertEqual(SystemNotifier.content(for: notice, customTools: []).body, "Pronto")
    }

    func testNotificationIsOffByDefault() {
        let suite = UserDefaults(suiteName: "SystemNotifierTests-\(UUID().uuidString)")!
        XCTAssertNil(suite.object(forKey: "systemNotification"))
        XCTAssertFalse(suite.object(forKey: "systemNotification") as? Bool ?? false)
    }

    func testPostDoesNothingWhenDisabledOrOutsideABundle() {
        // `swift test` is not an .app, so this must neither crash nor throw.
        let notice = NotchNotice(tool: .shell, project: nil, phrase: "x", sessionID: "s")
        SystemNotifier.shared.post(notice)
        SystemNotifier.shared.requestAuthorization { XCTAssertEqual($0, .unsupported) }
    }
}
