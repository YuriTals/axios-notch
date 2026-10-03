import Foundation

/// A dotted version such as `1.0.1` (a leading `v` and anything after `-` are ignored).
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        var clean = text.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("v") || clean.hasPrefix("V") { clean.removeFirst() }
        clean = clean.split(separator: "-", maxSplits: 1).first.map(String.init) ?? clean
        let numbers = clean.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(where: { $0 == nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        for i in 0..<count {
            let (x, y) = (i < a.parts.count ? a.parts[i] : 0, i < b.parts.count ? b.parts[i] : 0)
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// What the app needs to know about a GitHub release.
struct ReleaseInfo: Equatable {
    let tag: String
    let version: AppVersion
    let notes: String
    let pageURL: URL
    /// The `.dmg` asset, when the release has one.
    let dmgURL: URL?
    /// SHA-256 of the `.dmg`, read from the release notes. Without it the app
    /// never installs by itself.
    let sha256: String?
}

enum ReleaseParser {
    /// Parses `GET /repos/{owner}/{repo}/releases/latest`.
    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (json["draft"] as? Bool) != true, (json["prerelease"] as? Bool) != true,
              let tag = json["tag_name"] as? String, let version = AppVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let notes = json["body"] as? String ?? ""
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        return ReleaseInfo(tag: tag, version: version, notes: notes, pageURL: page, dmgURL: dmg, sha256: sha256(in: notes))
    }

    /// The first 64-digit hexadecimal string in the notes, lowercased.
    static func sha256(in notes: String) -> String? {
        guard let range = notes.range(of: "(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])", options: .regularExpression) else { return nil }
        return notes[range].lowercased()
    }
}
