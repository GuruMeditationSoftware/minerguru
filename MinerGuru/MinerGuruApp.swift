import SwiftUI
import AppKit

/// Couples the Dock icon to the dashboard window (see `DockPresence`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dock = DockPresence()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dock.start()
    }

    /// `minerguru://` links from widget clicks and Control Center controls.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { WidgetBridge.shared.handle(url: url) }
    }

    /// Closing the dashboard must not quit the app: it keeps running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MinerGuruApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MinerStore()
    @AppStorage(PrivacyMode.storageKey) private var hideSensitiveData = false

    private var redactor: Redactor { Redactor(isActive: hideSensitiveData) }

    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    init() {
        // Before any localized text is loaded: German on a German Mac, English otherwise, unless chosen in Settings.
        AppLanguage.applyAtLaunch()
        // The test host is this app: its runs must not end up in the user's files.
        guard !MinerGuruApp.isRunningTests else { return }
        DiagnosticLog.shared.activate()
        ChangeLog.shared.activate()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        DiagnosticLog.shared.write("app", "start version=\(version) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    var body: some Scene {
        // A single window: opening it again (menu bar, Dock) brings the existing one to the front.
        Window("MinerGuru", id: "main") {
            MainWindowView(store: store)
                .environment(\.redactor, redactor)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                    appDelegate.dock.applyAppIcon()
                }
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton { Text("Einstellungen…") }
                    .keyboardShortcut(",", modifiers: .command)
            }
            SidebarCommands()

            CommandGroup(after: .sidebar) {
                Toggle("Sensible Daten ausblenden", isOn: $hideSensitiveData)
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandMenu("Miner") {
                Button("Miner per IP hinzufügen…") {
                    store.showAddIPSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Lokales Netzwerk scannen…") {
                    store.showScannerSheet = true
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Alle Miner jetzt aktualisieren") {
                    Task { await store.refreshAllMiners() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarView(store: store, dock: appDelegate.dock)
                .environment(\.redactor, redactor)
        } label: {
            MenuBarLabel(text: store.menuBarSummaryText, store: store, dock: appDelegate.dock)
        }
        .menuBarExtraStyle(.window)

        Window("Einstellungen", id: SettingsView.windowID) {
            SettingsView(store: store)
                .environment(\.redactor, redactor)
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentMinSize)
    }
}

/// The menu bar text. It lives as long as the app, so it also lends widget clicks and the right-click menu
/// its way to open SwiftUI windows.
private struct MenuBarLabel: View {
    let text: String
    let store: MinerStore
    let dock: DockPresence
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(text)
            .monospacedDigit()
            .onAppear {
                let open = { [openWindow, dock] (id: String) in
                    dock.showDockIcon() // the app runs without Dock icon while no window is open
                    openWindow(id: id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                WidgetBridge.shared.openMainWindow = { open("main") }
                StatusItemMenu.shared.install(.init(
                    openDashboard: { open("main") },
                    openSettings: { open(SettingsView.windowID) },
                    refresh: { [store] in Task { await store.refreshAllMiners() } }
                ))
            }
    }
}
