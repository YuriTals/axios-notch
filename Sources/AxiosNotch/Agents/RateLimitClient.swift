import Foundation

/// Fetches real plan usage (% of the 5-hour and weekly windows) from the
/// providers, using the sign-in the CLIs already keep on this Mac. Tokens are
/// read per request, held only in memory, never logged, and never refreshed
/// here — refreshing would rotate the CLI's refresh token behind its back.
enum RateLimitClient {
    struct Failure: Error {
        let message: String
        /// The server's `Retry-After`, in seconds, when it sent one.
        var retryAfter: TimeInterval? = nil
    }

    /// The outcome, plus how long the server asked us to wait if it did.
    struct Result {
        let state: LimitState
        let succeeded: Bool
        let retryAfter: TimeInterval?
    }

    static func fetch(_ provider: AgentProvider) async -> Result {
        do {
            let limits: AgentRateLimits
            switch provider {
            case .claude: limits = try await fetchClaude()
            case .codex: limits = try await fetchCodex()
            }
            return Result(state: .available(limits), succeeded: true, retryAfter: nil)
        } catch let failure as Failure {
            return Result(state: .unavailable(failure.message), succeeded: false, retryAfter: failure.retryAfter)
        } catch {
            return Result(state: .unavailable(tr("Sem conexão com \(provider.displayName)", "Can't reach \(provider.displayName)")), succeeded: false, retryAfter: nil)
        }
    }

    // MARK: Claude

    private static func fetchClaude() async throws -> AgentRateLimits {
        guard let creds = claudeCredentials() else {
            throw Failure(message: tr("Entre no Claude Code para ver o limite", "Sign in to Claude Code to see the limit"))
        }
        if let expiresAt = creds.expiresAt, expiresAt <= Date().timeIntervalSince1970 * 1000 {
            throw Failure(message: tr("Sessão expirada — abra o Claude Code para renovar", "Session expired — open Claude Code to renew"))
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("axios-notch", forHTTPHeaderField: "User-Agent")
        let json = try await jsonResponse(for: request, provider: "Claude Code")
        guard let limits = RateLimitParser.claude(json, plan: creds.plan) else {
            throw Failure(message: tr("Resposta inesperada do Claude", "Unexpected response from Claude"))
        }
        return limits
    }

    private struct ClaudeCredentials {
        let accessToken: String
        let expiresAt: Double?
        let plan: String?
    }

    private static func claudeCredentials() -> ClaudeCredentials? {
        let raw = keychainPassword(service: "Claude Code-credentials") ?? credentialsFile()
        guard let raw,
              let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return ClaudeCredentials(
            accessToken: token,
            expiresAt: (oauth["expiresAt"] as? NSNumber)?.doubleValue,
            plan: oauth["subscriptionType"] as? String
        )
    }

    private static func keychainPassword(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func credentialsFile() -> String? {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return try? String(contentsOf: base.appendingPathComponent(".credentials.json"), encoding: .utf8)
    }

    // MARK: Codex

    private static func fetchCodex() async throws -> AgentRateLimits {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty
        else { throw Failure(message: tr("Entre no Codex para ver o limite", "Sign in to Codex to see the limit")) }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        if let account = tokens["account_id"] as? String ?? accountID(fromIDToken: tokens["id_token"] as? String) {
            request.setValue(account, forHTTPHeaderField: "chatgpt-account-id")
        }
        let json = try await jsonResponse(for: request, provider: "Codex")
        guard let limits = RateLimitParser.codex(json) else {
            throw Failure(message: tr("Resposta inesperada do Codex", "Unexpected response from Codex"))
        }
        return limits
    }

    private static func accountID(fromIDToken token: String?) -> String? {
        guard let payload = token?.split(separator: ".").dropFirst().first else { return nil }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = object["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }
        return auth["chatgpt_account_id"] as? String
    }

    // MARK: Shared

    private static func jsonResponse(for request: URLRequest, provider: String) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            throw Failure(message: tr("Sessão expirada — abra o \(provider) para renovar", "Session expired — open \(provider) to renew"))
        }
        if status == 429 {
            let wait = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw Failure(message: tr("\(provider) limitou as consultas", "\(provider) rate-limited the requests"), retryAfter: wait)
        }
        guard (200..<300).contains(status) else {
            throw Failure(message: tr("\(provider) respondeu \(status)", "\(provider) responded \(status)"))
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}
