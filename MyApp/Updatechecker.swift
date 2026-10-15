import SwiftUI
import Combine

enum UpdateState {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL, notes: String)
    case failed(String)
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    let name: String?
    let body: String?
}

/// Compares the installed version with the latest GitHub release.
/// It only tells people a new version exists and opens the download page.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    // Your GitHub repository
    static let owner = "Saumyadeep4"
    static let repo = "MusicControl"

    @Published var state: UpdateState = .idle
    @Published var lastChecked: Date? = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date

    var hasUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var versionDescription: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? currentVersion : "\(currentVersion) (\(build))"
    }

    /// Called when the app starts. Checks at most once a day, and only if the switch is on.
    func checkOnLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true else { return }
        if let last = defaults.object(forKey: "lastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        Task { await check(silently: true) }
    }

    /// `silently` = don't show errors (used for the automatic check).
    func check(silently: Bool = false) async {
        state = .checking

        guard let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest") else {
            state = .idle
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

            switch http.statusCode {
            case 200:
                break
            case 404:
                state = silently ? .idle : .failed("No releases were found yet.")
                return
            case 403, 429:
                state = silently ? .idle : .failed("GitHub is limiting requests right now. Try again later.")
                return
            default:
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = try decoder.decode(GitHubRelease.self, from: data)

            let now = Date()
            lastChecked = now
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")

            if Self.isNewer(release.tagName, than: currentVersion),
               let pageURL = URL(string: release.htmlUrl) {
                state = .available(version: Self.clean(release.tagName),
                                   url: pageURL,
                                   notes: Self.trimmed(release.body ?? ""))
            } else {
                state = .upToDate
            }
        } catch {
            state = silently ? .idle : .failed("Couldn't check for updates. Check your internet connection and try again.")
        }
    }

    // MARK: - Helpers

    private static func clean(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    /// "v2.1" is newer than "2.0.3", "v2.0" is not newer than "2.0.0"
    private static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            clean(s).split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let a = parts(remote)
        let b = parts(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func trimmed(_ notes: String) -> String {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 800 ? String(text.prefix(800)) + "…" : text
    }
}
