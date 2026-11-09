import Foundation

/// Reads GitHub's answer about the latest release and compares versions.
enum UpdateCheck {
    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool?
        let prerelease: Bool?
    }

    /// The version of a published, final release, without a leading `v`; `nil` for anything else.
    static func version(fromResponse data: Data) -> String? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true else { return nil }
        let tag = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return tag.wholeMatch(of: /\d+(\.\d+){0,3}/) == nil ? nil : tag
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

/// Asks GitHub once a day whether a newer version exists. It only tells the user: nothing is downloaded or installed.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle, checking, upToDate, failed
    }

    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// How often `start()` looks whether a check is due. A failed check is repeated at this pace.
    private static let wakeInterval: Duration = .seconds(60 * 60)

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var status = Status.idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var dismissedVersion: String?

    /// A version newer than this app, if the last answer named one.
    var availableVersion: String? {
        guard let latestVersion, UpdateCheck.isNewer(latestVersion, than: currentVersion) else { return nil }
        return latestVersion
    }

    /// The version the overview announces.
    var bannerVersion: String? {
        guard isEnabled, let availableVersion, availableVersion != dismissedVersion else { return nil }
        return availableVersion
    }

    private let defaults: UserDefaults
    private let currentVersion: String
    private let url: URL
    private let fetch: Fetch
    private var loop: Task<Void, Never>?

    private static let enabledKey = "MinerGuru.UpdateCheckEnabled.v1"
    private static let lastCheckKey = "MinerGuru.UpdateLastCheck.v1"
    private static let latestKey = "MinerGuru.UpdateLatestVersion.v1"
    private static let dismissedKey = "MinerGuru.UpdateDismissedVersion.v1"

    init(
        defaults: UserDefaults,
        currentVersion: String = AppInfo.version,
        url: URL = AppInfo.updateCheckURL,
        fetch: @escaping Fetch = UpdateChecker.fetchFromNetwork
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.url = url
        self.fetch = fetch
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.latestVersion = defaults.string(forKey: Self.latestKey)
        self.dismissedVersion = defaults.string(forKey: Self.dismissedKey)
    }

    deinit { loop?.cancel() }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(for: Self.wakeInterval)
            }
        }
    }

    func checkIfDue(now: Date = Date()) async {
        guard isEnabled, status != .checking else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date
        if let last, now.timeIntervalSince(last) < Self.checkInterval, now >= last { return }
        await check(now: now)
    }

    func check(now: Date = Date()) async {
        guard status != .checking else { return }
        status = .checking
        guard let (data, code) = try? await fetch(url), code == 200,
              let version = UpdateCheck.version(fromResponse: data) else {
            status = .failed
            return
        }
        latestVersion = version
        defaults.set(version, forKey: Self.latestKey)
        defaults.set(now, forKey: Self.lastCheckKey)
        status = .upToDate
    }

    func dismissBanner() {
        dismissedVersion = availableVersion
        defaults.set(dismissedVersion, forKey: Self.dismissedKey)
    }

    private nonisolated static func fetchFromNetwork(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MinerGuru/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
