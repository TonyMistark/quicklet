import Combine
import Foundation

/// Where the running copy stands relative to the published releases.
///
/// `upToDate` and `failed` are one-shot feedback: they flash briefly and fall
/// back to `idle`. `available` sticks until the user updates, because that is
/// the one state that asks for an action.
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    /// A newer release exists. `sources` lists the places that reported the
    /// same version (GitHub first, Gitee second); a source without a zip
    /// asset makes the UI fall back to opening its release page.
    case available(version: String, sources: [UpdateSource])
    case failed
}

/// A zip attached to a release: what "update now" downloads.
struct UpdateAsset: Equatable {
    let url: URL
    let name: String
    let byteCount: Int

    var megabytes: String {
        byteCount > 0 ? String(format: "%.1f MB", Double(byteCount) / 1_000_000) : ""
    }

    /// Picks `Quicklet-<version>.zip` out of a release's assets.
    static func archive(
        named pieces: [(name: String, url: URL, size: Int)],
        version: String?
    ) -> UpdateAsset? {
        let candidates = pieces.compactMap { piece -> UpdateAsset? in
            guard piece.name.lowercased().hasSuffix(".zip") else { return nil }
            return UpdateAsset(url: piece.url, name: piece.name, byteCount: piece.size)
        }
        guard candidates.count > 1, let version else { return candidates.first }
        return candidates.first { $0.name.localizedCaseInsensitiveContains(version) }
            ?? candidates.first
    }
}

/// One place a build can be downloaded from.
struct UpdateSource: Equatable {
    let name: String
    let asset: UpdateAsset?
    let releaseURL: URL
}

/// Checks the release feeds at most once a day and reports whether something
/// newer is out.
///
/// Three deliberate restraints:
/// 1. no bundled downloader for the check itself - it only reads the public
///    JSON, so a broken feed can never block the app;
/// 2. failures stay silent on launch - a Finder tool must not pop dialogs
///    while the user is working;
/// 3. throttling - 24 h after a success, 1 h after a failure.
///
/// Both feeds are queried concurrently and the highest version wins, so a
/// release published on GitHub but not yet mirrored to Gitee still shows up,
/// and a single unreachable host does not break the check.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Configuration {
        struct Source {
            /// Shown in the UI ("GitHub", "Gitee").
            let name: String
            /// "Latest release" endpoint. GitHub and Gitee API v5 are close
            /// enough that one decoder handles both.
            let endpoint: URL
            /// Release page template (`{}` is replaced by the tag). Gitee's
            /// JSON carries no `html_url`, so the page URL is built here.
            var pageTemplate: String = ""

            func page(forTag tag: String) -> URL? {
                guard !pageTemplate.isEmpty else { return nil }
                return URL(string: pageTemplate.replacingOccurrences(of: "{}", with: tag))
            }
        }

        var currentVersion: String
        var sources: [Source]
        var interval: TimeInterval
        var retryInterval: TimeInterval

        static let `default` = Configuration(
            currentVersion: AppInfo.shortVersion,
            sources: [
                Source(
                    name: "GitHub",
                    endpoint: URL(string: "https://api.github.com/repos/TonyMistark/quicklet/releases/latest")!
                ),
                Source(
                    name: "Gitee",
                    endpoint: URL(string: "https://gitee.com/api/v5/repos/Micestark/quicklet/releases/latest")!,
                    pageTemplate: "https://gitee.com/Micestark/quicklet/releases/tag/{}"
                ),
            ],
            interval: 24 * 60 * 60,
            retryInterval: 60 * 60
        )
    }

    /// Why one source failed. `reason` is already a sentence meant for the UI.
    struct SourceFailure: Equatable, Identifiable {
        let source: String
        let reason: String
        var id: String { source }
    }

    typealias Fetch = @Sendable (Configuration.Source) async throws -> (Data, URLResponse)

    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var lastFailures: [SourceFailure] = []

    /// How long a one-shot status stays visible.
    private static let flashDuration: TimeInterval = 4

    private let configuration: Configuration
    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: Fetch
    private var resetTask: Task<Void, Never>?

    private enum Key {
        static let lastCheck = "quicklet.updates.lastCheck"
        static let lastCheckSucceeded = "quicklet.updates.lastCheckOK"
    }

    init(
        configuration: Configuration = .default,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping Fetch = UpdateChecker.fetchLatestRelease
    ) {
        self.configuration = configuration
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
    }

    var isChecking: Bool { status == .checking }

    var currentVersion: String { configuration.currentVersion }

    /// Called at launch: only hits the network when the throttle allows it.
    func checkIfDue() async {
        await check(force: false)
    }

    /// The "check now" button bypasses the throttle.
    func check(force: Bool) async {
        guard status != .checking else { return }
        guard force || isDue else { return }

        resetTask?.cancel()
        status = .checking
        lastFailures = []

        var found: [(source: Configuration.Source, release: RemoteRelease)] = []
        var failed: [(source: Configuration.Source, error: Error)] = []
        await withTaskGroup(of: (Configuration.Source, Result<RemoteRelease, Error>).self) { group in
            for source in configuration.sources {
                group.addTask { [fetch] in
                    (source, await Self.load(source, fetch: fetch))
                }
            }
            for await (source, result) in group {
                switch result {
                case .success(let release): found.append((source, release))
                case .failure(let error): failed.append((source, error))
                }
            }
        }

        guard !found.isEmpty else {
            // Before the first release every feed answers 404. That is not a
            // failure worth showing: nothing newer exists, so report current.
            let allMissing = !failed.isEmpty && failed.allSatisfy {
                Self.httpStatus(of: $0.error) == 404
            }
            if allMissing {
                Diagnostics.log("update check: no releases published yet")
                recordAttempt(succeeded: true)
                flash(.upToDate(version: configuration.currentVersion))
                return
            }

            lastFailures = failed
                .sorted { index(of: $0.source) < index(of: $1.source) }
                .map { SourceFailure(source: $0.source.name, reason: Self.reason(for: $0.error)) }
            Diagnostics.log("update check failed: " + lastFailures.map { "\($0.source)=\($0.reason)" }.joined(separator: ", "))
            recordAttempt(succeeded: false)
            flash(.failed)
            return
        }

        recordAttempt(succeeded: true)
        evaluate(found)
    }

    // MARK: - Loading one source

    /// Retries once on a transient failure: a single DNS hiccup or TLS reset
    /// should not read as "no updates available".
    ///
    /// 403/429 (rate limit), 404 (nothing published there yet) and undecodable
    /// JSON are not retried - waiting 15 s again would not help.
    nonisolated private static func load(
        _ source: Configuration.Source,
        fetch: @escaping Fetch
    ) async -> Result<RemoteRelease, Error> {
        var lastError: Error = UpdateError.badResponse
        for attempt in 0..<2 {
            do {
                let (data, response) = try await fetch(source)
                guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
                guard (200..<300).contains(http.statusCode) else {
                    throw UpdateError.http(status: http.statusCode)
                }
                return .success(try JSONDecoder().decode(RemoteRelease.self, from: data))
            } catch {
                lastError = error
                if Task.isCancelled { break }
                if let code = Self.httpStatus(of: error), [403, 404, 429].contains(code) { break }
                if error is DecodingError { break }
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }
        return .failure(lastError)
    }

    /// Turns an error into something readable in the about page. Deliberately
    /// no domain codes: that line has to be understood at a glance.
    nonisolated static func reason(for error: Error) -> String {
        if let status = httpStatus(of: error) {
            if status == 403 || status == 429 { return "请求过于频繁，稍后再试" }
            if status == 404 { return "这个源还没有发布版本" }
            return "HTTP \(status)"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时"
            case .notConnectedToInternet, .networkConnectionLost: return "网络未连接"
            default: return "网络错误"
            }
        }
        if error is DecodingError { return "返回内容无法解析" }
        return "网络错误"
    }

    nonisolated private static func httpStatus(of error: Error) -> Int? {
        if case UpdateError.http(let status) = error { return status }
        return nil
    }

    // MARK: - Deciding

    private func index(of source: Configuration.Source) -> Int {
        configuration.sources.firstIndex { $0.endpoint == source.endpoint } ?? .max
    }

    private func evaluate(_ releases: [(source: Configuration.Source, release: RemoteRelease)]) {
        guard let current = AppVersion(configuration.currentVersion) else {
            flash(.failed)
            return
        }

        // Feeds can disagree (a tag pushed to GitHub but not yet to Gitee):
        // the higher version wins, and every source reporting it is kept so
        // the user can pick a download location. Sorting by configured order
        // keeps "primary source" stable regardless of which response landed
        // first.
        var bestVersion: AppVersion?
        var sources: [UpdateSource] = []
        for piece in releases.sorted(by: { index(of: $0.source) < index(of: $1.source) }) {
            guard !piece.release.draft, !piece.release.prerelease,
                  let version = AppVersion(piece.release.tagName) else { continue }
            if let best = bestVersion {
                if version > best {
                    bestVersion = version
                    sources = [piece.release.updateSource(on: piece.source)]
                } else if version == best {
                    sources.append(piece.release.updateSource(on: piece.source))
                }
            } else {
                bestVersion = version
                sources = [piece.release.updateSource(on: piece.source)]
            }
        }

        guard let latest = bestVersion else {
            flash(.upToDate(version: configuration.currentVersion))
            return
        }
        if latest > current {
            Diagnostics.log("update available: \(latest.description) (current \(configuration.currentVersion))")
            status = .available(version: latest.description, sources: sources)
        } else {
            Diagnostics.log("update check ok: \(current.description) is current")
            flash(.upToDate(version: current.description))
        }
    }

    // MARK: - Throttling

    private var isDue: Bool {
        guard let last = defaults.object(forKey: Key.lastCheck) as? Double else { return true }
        let succeeded = defaults.bool(forKey: Key.lastCheckSucceeded)
        let interval = succeeded ? configuration.interval : configuration.retryInterval
        return now().timeIntervalSince1970 - last >= interval
    }

    private func recordAttempt(succeeded: Bool) {
        defaults.set(now().timeIntervalSince1970, forKey: Key.lastCheck)
        defaults.set(succeeded, forKey: Key.lastCheckSucceeded)
    }

    private func flash(_ value: UpdateStatus) {
        status = value
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.flashDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.status == value else { return }
            self.status = .idle
        }
    }

    // MARK: - Default network implementation

    nonisolated private static func fetchLatestRelease(
        from source: Configuration.Source
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: source.endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects requests without a User-Agent with 403.
        request.setValue("Quicklet/\(Configuration.default.currentVersion)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }
}

/// Release JSON from GitHub and Gitee. Both omit fields the other has
/// (`html_url` only on GitHub, `draft`/`prerelease` only there too), so every
/// optional is decoded leniently - a missing key is not an error.
struct RemoteRelease: Decodable {
    let tagName: String
    let htmlURL: URL?
    let draft: Bool
    let prerelease: Bool
    private let assets: [Asset]?

    init(
        tagName: String,
        htmlURL: URL? = nil,
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [Asset]? = nil
    ) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try? container.decode(URL.self, forKey: .htmlURL)
        draft = (try? container.decode(Bool.self, forKey: .draft)) ?? false
        prerelease = (try? container.decode(Bool.self, forKey: .prerelease)) ?? false
        assets = try? container.decode([Asset].self, forKey: .assets)
    }

    func updateSource(on source: UpdateChecker.Configuration.Source) -> UpdateSource {
        UpdateSource(
            name: source.name,
            asset: asset,
            releaseURL: htmlURL ?? source.page(forTag: tagName) ?? fallbackPage
        )
    }

    /// Neither the feed nor a template gives a page: the releases list is the
    /// least surprising place to land.
    private var fallbackPage: URL {
        URL(string: "https://github.com/TonyMistark/quicklet/releases")!
    }

    var asset: UpdateAsset? {
        UpdateAsset.archive(
            named: (assets ?? []).compactMap { piece in
                guard let url = piece.downloadURL, let name = piece.name, !name.isEmpty else { return nil }
                return (name, url, piece.size ?? -1)
            },
            version: AppVersion(tagName)?.description
        )
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    struct Asset: Decodable {
        let name: String?
        let size: Int?
        let downloadURL: URL?

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case downloadURL = "browser_download_url"
        }
    }
}

private enum UpdateError: Error {
    case badResponse
    /// Non-2xx: the status is kept so rate limiting can be told apart from an
    /// empty feed.
    case http(status: Int)
}
