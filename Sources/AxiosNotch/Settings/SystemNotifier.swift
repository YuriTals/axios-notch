import Foundation
import UserNotifications

/// Optional macOS notification for "answer ready" and "waiting for you", for
/// when the notch is out of sight (another Space, a full-screen app). Off by
/// default; turning it on asks macOS for permission.
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    /// Called with the session id when the user clicks a notification.
    var onOpen: ((String) -> Void)?

    /// `UNUserNotificationCenter` crashes outside an app bundle (`swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    func start() {
        center?.delegate = self
    }

    enum Access: Equatable {
        case allowed
        /// The user switched notifications off for the app in System Settings.
        case denied
        /// Not running from an .app, so macOS cannot deliver them.
        case unsupported
        case failed(String)
    }

    /// Asks for permission when macOS has not been asked yet; otherwise reports
    /// the answer it already has (asking again would silently return `false`).
    func requestAuthorization(completion: @escaping (Access) -> Void) {
        guard let center else { return completion(.unsupported) }
        func finish(_ access: Access) { DispatchQueue.main.async { completion(access) } }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                finish(.allowed)
            case .denied:
                finish(.denied)
            default:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error { finish(.failed(error.localizedDescription)) }
                    else { finish(granted ? .allowed : .denied) }
                }
            }
        }
    }

    static func content(for notice: NotchNotice, customTools: [CustomTool]) -> (title: String, body: String) {
        let title = notice.tool.displayName(customTools: customTools)
        let body = [notice.project, notice.phrase].compactMap { $0 }.joined(separator: " · ")
        return (title, body)
    }

    func post(_ notice: NotchNotice, settings: AppSettings = .shared) {
        guard settings.systemNotification, let center else { return }
        let text = Self.content(for: notice, customTools: settings.customTools)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        if let id = notice.sessionID { content.userInfo = ["sessionID": id] }
        // The chosen sound already plays through `NoticeSound`; no double beep.
        center.add(UNNotificationRequest(identifier: notice.id.uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["sessionID"] as? String {
            DispatchQueue.main.async { self.onOpen?(id) }
        }
        completionHandler()
    }

    /// Show it even when Axios Notch is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
