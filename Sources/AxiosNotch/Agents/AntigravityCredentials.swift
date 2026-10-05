import Foundation

/// Read existing CLI sign-in only. Refresh tokens and account details are discarded.
struct AntigravityCredentials {
    let accessToken: String
    let expiresAt: Date

    static func parse(_ raw: String) -> AntigravityCredentials? {
        let prefix = "go-keyring-base64:"
        let data = raw.hasPrefix(prefix)
            ? Data(base64Encoded: String(raw.dropFirst(prefix.count))) : raw.data(using: .utf8)
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = root["token"] as? [String: Any],
              let access = token["access_token"] as? String, !access.isEmpty,
              let expiry = token["expiry"] as? String,
              let date = ClaudeUsageReader.parseTimestamp(expiry) else { return nil }
        return AntigravityCredentials(accessToken: access, expiresAt: date)
    }
}
