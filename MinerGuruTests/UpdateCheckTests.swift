import Foundation
import Testing
@testable import MinerGuru

@Suite("Update check")
struct UpdateCheckTests {
    private func json(_ tag: String, prerelease: Bool = false) -> Data {
        Data(#"{"tag_name":"\#(tag)","draft":false,"prerelease":\#(prerelease)}"#.utf8)
    }

    @Test func readsTheVersionOfARelease() {
        #expect(UpdateCheck.version(fromResponse: json("v1.9.0")) == "1.9.0")
        #expect(UpdateCheck.version(fromResponse: json("2.0")) == "2.0")
    }

    @Test func ignoresPrereleasesAndOtherTags() {
        #expect(UpdateCheck.version(fromResponse: json("v2.0.0", prerelease: true)) == nil)
        #expect(UpdateCheck.version(fromResponse: json("v2.0.0-beta")) == nil)
        #expect(UpdateCheck.version(fromResponse: json("nightly")) == nil)
        #expect(UpdateCheck.version(fromResponse: Data("not json".utf8)) == nil)
    }

    @Test func comparesNumbersNotText() {
        #expect(UpdateCheck.isNewer("1.10.0", than: "1.9.9"))
        #expect(UpdateCheck.isNewer("1.8.3", than: "1.8.2"))
        #expect(UpdateCheck.isNewer("1.9", than: "1.8.2"))
        #expect(!UpdateCheck.isNewer("1.8.2", than: "1.8.2"))
        #expect(!UpdateCheck.isNewer("1.8", than: "1.8.0"))
        #expect(!UpdateCheck.isNewer("1.7.9", than: "1.8.0"))
    }

    @MainActor private func checker(
        tag: String = "v1.9.0", code: Int = 200, current: String = "1.8.2", defaults: UserDefaults? = nil
    ) -> UpdateChecker {
        let answer = json(tag)
        return UpdateChecker(
            defaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!,
            currentVersion: current,
            url: URL(string: "http://localhost/latest")!,
            fetch: { _ in (answer, code) }
        )
    }

    @MainActor @Test func announcesANewerVersionUntilDismissed() async {
        let updates = checker()
        await updates.check()
        #expect(updates.status == .upToDate)
        #expect(updates.bannerVersion == "1.9.0")
        updates.dismissBanner()
        #expect(updates.bannerVersion == nil)
        #expect(updates.availableVersion == "1.9.0")
    }

    @MainActor @Test func aLaterVersionShowsAgainAfterDismissing() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = checker(defaults: defaults)
        await first.check()
        first.dismissBanner()
        let second = checker(tag: "v1.9.1", defaults: defaults)
        await second.check()
        #expect(second.bannerVersion == "1.9.1")
    }

    @MainActor @Test func staysQuietWhenCurrentOrTurnedOff() async {
        let current = checker(tag: "v1.8.2")
        await current.check()
        #expect(current.availableVersion == nil)
        let off = checker()
        off.isEnabled = false
        await off.checkIfDue()
        #expect(off.latestVersion == nil)
    }

    @MainActor @Test func aFailedCheckKeepsTheLastAnswerAndIsRetried() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let missing = checker(code: 404, defaults: defaults)
        await missing.checkIfDue()
        #expect(missing.status == .failed)
        #expect(missing.latestVersion == nil)
        let next = checker(defaults: defaults)
        await next.checkIfDue()
        #expect(next.latestVersion == "1.9.0")
    }

    @MainActor @Test func asksAtMostOnceADay() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let start = Date(timeIntervalSince1970: 1_000_000)
        await checker(defaults: defaults).checkIfDue(now: start)
        let later = checker(tag: "v2.0.0", defaults: defaults)
        await later.checkIfDue(now: start.addingTimeInterval(3600))
        #expect(later.latestVersion == "1.9.0")
        await later.checkIfDue(now: start.addingTimeInterval(UpdateChecker.checkInterval + 1))
        #expect(later.latestVersion == "2.0.0")
    }
}
