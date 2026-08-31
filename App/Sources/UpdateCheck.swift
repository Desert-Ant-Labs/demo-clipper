import Foundation
import Observation

/// Whether a newer Clipper has been released.
///
/// Reads the latest release tag and links to its page. Nothing is installed,
/// and nothing arriving over the network is run.
///
/// The launch check speaks only when there is a newer release. Being told you
/// are up to date is worth a sheet when you asked and an interruption when you
/// did not.
@MainActor
@Observable
final class UpdateCheck {
    /// The answer to one check, held until it is dismissed.
    enum Answer: Equatable {
        case current(String)
        case available(version: String, page: URL)
        case failed(String)
    }

    private(set) var isChecking = false
    var answer: Answer?

    /// Public, so the check carries no token.
    private static let endpoint = URL(
        string: "https://api.github.com/repos/Desert-Ant-Labs/demo-clipper/releases/latest")!

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: URL
    }

    /// The menu item's check, which always answers.
    func check() async {
        await check(announcing: true)
    }

    /// The launch check, silent unless there is something newer to open.
    func checkQuietly() async {
        await check(announcing: false)
    }

    private func check(announcing: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetch()
            let latest = Self.number(in: release.tagName)
            if Self.isNewer(latest, than: Self.running) {
                answer = .available(version: latest, page: release.htmlUrl)
            } else if announcing {
                answer = .current(Self.running)
            }
        } catch {
            if announcing { answer = .failed(error.localizedDescription) }
        }
    }

    private func fetch() async throws -> Release {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Release.self, from: data)
    }

    /// What this build calls itself.
    nonisolated static var running: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// A release tag without its `v`, so it compares against a bundle version.
    nonisolated static func number(in tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numeric rather than lexical: `1.10` follows `1.9`.
    nonisolated static func isNewer(_ candidate: String, than running: String) -> Bool {
        guard !running.isEmpty, !candidate.isEmpty else { return false }
        return candidate.compare(running, options: .numeric) == .orderedDescending
    }
}
