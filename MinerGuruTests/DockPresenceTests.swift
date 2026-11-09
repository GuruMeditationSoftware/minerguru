import Testing
@testable import MinerGuru

@Suite("Dock icon follows the windows")
struct DockPresenceTests {
    typealias Window = DockPresence.WindowTraits

    @Test func visibleDashboardNeedsDockIcon() {
        #expect(DockPresence.needsDockIcon(windows: [Window(isVisible: true)]))
    }

    @Test func noWindowsMeansMenuBarOnly() {
        #expect(!DockPresence.needsDockIcon(windows: []))
        #expect(!DockPresence.needsDockIcon(windows: [Window(isVisible: false)]))
    }

    @Test func menuBarPopoverNeverCounts() {
        #expect(!DockPresence.needsDockIcon(windows: [Window(isVisible: true, isPanel: true)]))
    }

    @Test func untitledHelperWindowsNeverCount() {
        #expect(!DockPresence.needsDockIcon(windows: [Window(isVisible: true, isTitled: false)]))
    }

    @Test func minimizedWindowKeepsDockIcon() {
        #expect(DockPresence.needsDockIcon(windows: [Window(isVisible: false, isMiniaturized: true)]))
    }

    @Test func dashboardOutweighsPopover() {
        let windows = [Window(isVisible: true, isPanel: true), Window(isVisible: true)]
        #expect(DockPresence.needsDockIcon(windows: windows))
    }
}
