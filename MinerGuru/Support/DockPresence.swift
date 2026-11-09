import AppKit

/// Keeps the Dock icon in sync with the app's windows: with at least one regular window (dashboard,
/// settings) the app is a normal app; once the last one is closed it lives on in the menu bar only.
@MainActor
final class DockPresence {
    /// The properties of a window that decide whether the app needs a Dock icon.
    struct WindowTraits: Equatable {
        var isVisible: Bool
        var isMiniaturized: Bool
        var isPanel: Bool
        var isTitled: Bool

        init(isVisible: Bool, isMiniaturized: Bool = false, isPanel: Bool = false, isTitled: Bool = true) {
            self.isVisible = isVisible
            self.isMiniaturized = isMiniaturized
            self.isPanel = isPanel
            self.isTitled = isTitled
        }

        @MainActor
        init(_ window: NSWindow) {
            self.init(isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                      isPanel: window is NSPanel, isTitled: window.styleMask.contains(.titled))
        }

        /// Panels (the menu bar popover) and untitled helper windows never count; a minimized window does,
        /// because it still lives in the Dock.
        var isRegularWindow: Bool { !isPanel && isTitled && (isVisible || isMiniaturized) }
    }

    nonisolated static func needsDockIcon(windows: [WindowTraits]) -> Bool {
        windows.contains(where: \.isRegularWindow)
    }

    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
                // The closing window still counts as visible inside this notification; look again afterwards.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.update()
                }
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.update() }
            },
        ]
    }

    /// Shows the Dock icon right away (used before a window is opened from the menu bar).
    func showDockIcon() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        applyAppIcon()
    }

    func applyAppIcon() {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    private func update() {
        if Self.needsDockIcon(windows: NSApp.windows.map(WindowTraits.init)) {
            showDockIcon()
        } else if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
