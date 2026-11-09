import AppKit

/// UI language. Default follows the Mac: German if the system language is German, English otherwise.
/// The choice is applied through `AppleLanguages` and takes effect after a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case german = "de"
    case english = "en"

    var id: String { rawValue }

    static let storageKey = "MinerGuru.AppLanguage.v1"

    var title: String {
        switch self {
        case .system: return String(localized: "Systemsprache")
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The language code (`de` / `en`) a setting resolves to for the given system languages.
    static func resolvedCode(for setting: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch setting {
        case .german: return "de"
        case .english: return "en"
        case .system: return preferredLanguages.first?.lowercased().hasPrefix("de") == true ? "de" : "en"
        }
    }

    /// Language code the running process was started with (set by `applyAtLaunch`).
    @MainActor private(set) static var launchCode: String?

    /// Called once at app start, before any localized text is loaded.
    @MainActor
    static func applyAtLaunch(defaults: UserDefaults = .standard) {
        launchCode = apply(stored(in: defaults), defaults: defaults)
    }

    /// Points the app's localization at the chosen language and returns its code (`de` / `en`).
    @discardableResult
    static func apply(_ setting: AppLanguage, defaults: UserDefaults = .standard) -> String {
        let code = resolvedCode(for: setting, preferredLanguages: systemLanguages)
        defaults.set(setting.rawValue, forKey: storageKey)
        defaults.set([code], forKey: "AppleLanguages")
        return code
    }

    /// True if `setting` would show a different language than the running app, i.e. a restart is needed.
    @MainActor
    static func needsRestart(for setting: AppLanguage) -> Bool {
        launchCode.map { $0 != resolvedCode(for: setting, preferredLanguages: systemLanguages) } ?? false
    }

    /// The Mac's own language list. `Locale.preferredLanguages` would already contain the app's override.
    private static var systemLanguages: [String] {
        CFPreferencesCopyValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
            ?? Locale.preferredLanguages
    }

    /// Restarts the app so a new language takes effect.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Log.app.info("Neustart für Sprachwechsel")
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            if let error {
                Log.app.error("Neustart fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                return
            }
            Log.app.info("Neue Instanz gestartet: \(app?.processIdentifier ?? 0)")
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
