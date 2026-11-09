import Foundation
import Testing
@testable import MinerGuru

@Suite("App language")
struct AppLanguageTests {
    @Test(arguments: [
        (["de-DE", "en-US"], "de"),
        (["de-AT"], "de"),
        (["en-GB", "de-DE"], "en"),
        (["fr-FR"], "en"),
        ([], "en"),
    ])
    func systemSettingFollowsTheMac(languages: [String], expected: String) {
        #expect(AppLanguage.resolvedCode(for: .system, preferredLanguages: languages) == expected)
    }

    @Test func explicitChoiceWins() {
        #expect(AppLanguage.resolvedCode(for: .english, preferredLanguages: ["de-DE"]) == "en")
        #expect(AppLanguage.resolvedCode(for: .german, preferredLanguages: ["en-US"]) == "de")
    }

    @Test func applyStoresChoiceAndOverride() {
        let suite = "MinerGuruTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppLanguage.stored(in: defaults) == .system)
        AppLanguage.apply(.english, defaults: defaults)
        #expect(AppLanguage.stored(in: defaults) == .english)
        // Read the stored domain: a test run with -testLanguage overrides AppleLanguages in the argument domain.
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["en"])
    }
}
