import AppKit

/// Right-click (or Control-click) on the menu bar item opens a short menu with the main commands, as in
/// most menu bar apps. SwiftUI's `MenuBarExtra` has no hook for that, so a local event monitor takes the
/// click off the status item's window before the extra sees it; a left click still opens the popover.
///
/// The menu pops up below the item by itself. Handing it to the status item instead (its `menu`, or
/// `popUpMenu`) would add the system highlight, but SwiftUI turns any such click into opening the popover.
@MainActor
final class StatusItemMenu: NSObject {
    static let shared = StatusItemMenu()

    struct Actions {
        var openDashboard: () -> Void
        var openSettings: () -> Void
        var refresh: () -> Void
    }

    private var actions: Actions?
    private var monitor: Any?

    /// Called by the menu bar label, which lives as long as the app and can open SwiftUI windows.
    func install(_ actions: Actions) {
        self.actions = actions
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            let handled = MainActor.assumeIsolated { StatusItemMenu.shared.handle(event) }
            return handled ? nil : event
        }
    }

    /// Whether the click was a context click on the status item; then the menu has been shown.
    private func handle(_ event: NSEvent) -> Bool {
        let isContextClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isContextClick, let window = event.window, Self.isStatusItemWindow(window),
              let view = window.contentView else { return false }
        closePopover()
        // The point is the menu's top left corner; the status bar view is not flipped, so y = 0 is its bottom edge.
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -Self.menuGap), in: view)
        return true
    }

    /// The app has exactly one status item, so any status bar window in this process is ours.
    private static func isStatusItemWindow(_ window: NSWindow) -> Bool {
        window.className == "NSStatusBarWindow"
    }

    /// An open popover would sit under the menu; close it the way a click elsewhere would.
    private func closePopover() {
        for window in NSApp.windows where window.isVisible && window.className.contains("MenuBarExtraWindow") {
            window.close()
        }
    }

    /// The gap macOS leaves between the menu bar and the menus of other status items.
    private static let menuGap: CGFloat = 5

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "Dashboard öffnen"), #selector(openDashboard)))
        menu.addItem(item(String(localized: "Jetzt aktualisieren"), #selector(refresh)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Einstellungen…"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "MinerGuru beenden"), #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openDashboard() { actions?.openDashboard() }
    @objc private func openSettings() { actions?.openSettings() }
    @objc private func refresh() { actions?.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
}
