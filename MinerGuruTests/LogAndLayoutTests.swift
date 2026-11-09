import Foundation
import SwiftUI
import Testing
@testable import MinerGuru

@Suite("Live-log parsing")
struct LogParsingTests {
    @Test func parsesESPIDFLine() throws {
        let entry = try #require(MinerLogEntry.parse(rawLine: "\u{1B}[0;32mI (123456) stratum_task: Share accepted\u{1B}[0m"))
        #expect(entry.level == .info)
        #expect(entry.espTimestamp == "123456")
        #expect(entry.componentTag == "stratum_task")
        #expect(entry.message == "Share accepted")
        #expect(entry.isShareAccepted)
        #expect(!entry.isShareRejected)
    }

    @Test(arguments: [
        ("W (1) power: VR temp high", MinerLogLevel.warning),
        ("E (1) asic: no response", .error),
        ("D (1) wifi: rssi -60", .debug),
        ("V (1) wifi: verbose", .debug),
        ("something failed badly", .error),
        ("overheat mode on", .warning),
        ("plain message", .info),
    ])
    func levels(line: String, expected: MinerLogLevel) throws {
        #expect(try #require(MinerLogEntry.parse(rawLine: line)).level == expected)
    }

    @Test func rejectedShareIsAtLeastWarning() throws {
        let entry = try #require(MinerLogEntry.parse(rawLine: "I (5) stratum_api: result: false (rejected)"))
        #expect(entry.isShareRejected)
        #expect(entry.level == .warning)
    }

    @Test func blankLinesAreSkipped() {
        #expect(MinerLogEntry.parse(rawLine: "   ") == nil)
        #expect(MinerLogEntry.parse(rawLine: "\u{1B}[0m") == nil)
    }

    @Test func filtersBySearchTextAndCategory() throws {
        let share = try #require(MinerLogEntry.parse(rawLine: "I (1) stratum_task: Share accepted"))
        let warn = try #require(MinerLogEntry.parse(rawLine: "W (2) power: VR temp high"))

        #expect(share.matches(searchText: "ACCEPTED"))
        #expect(share.matches(searchText: "stratum"))
        #expect(share.matches(searchText: "  "))
        #expect(!share.matches(searchText: "fan"))

        #expect(share.matches(category: .sharesAndPool))
        #expect(!share.matches(category: .warningsAndErrors))
        #expect(warn.matches(category: .warningsAndErrors))
        #expect(warn.matches(category: .all))
    }

    @Test func exportLineFormat() throws {
        let entry = try #require(MinerLogEntry.parse(rawLine: "W (77) power: VR temp high", receivedAt: Date(timeIntervalSince1970: 0)))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        #expect(entry.formattedExportLine(dateFormatter: formatter) == "00:00 [W] (77) [power] VR temp high")
    }
}

@Suite("Layouts")
struct LayoutTests {
    @Test func flowLayoutWrapsWhenLineIsFull() {
        let layout = FlowLayout(horizontalSpacing: 10, verticalSpacing: 5)
        let sizes = [CGSize(width: 50, height: 20), CGSize(width: 50, height: 30), CGSize(width: 50, height: 10)]
        let result = layout.arrange(sizes: sizes, width: 120)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0), CGPoint(x: 0, y: 35)])
        #expect(result.size == CGSize(width: 110, height: 45))
    }

    @Test func flowLayoutPlacesOversizedItemOnItsOwnLine() {
        let layout = FlowLayout(horizontalSpacing: 10, verticalSpacing: 5)
        let result = layout.arrange(sizes: [CGSize(width: 300, height: 10)], width: 100)
        #expect(result.origins == [.zero])
        #expect(result.size.width == 300)
    }

    @Test(arguments: [(1000.0, 8, 4), (420.0, 8, 2), (100.0, 8, 1), (1000.0, 2, 2), (1000.0, 0, 1)])
    func adaptiveGridColumns(width: Double, items: Int, expected: Int) {
        let grid = AdaptiveGrid(minColumnWidth: 200, spacing: 12)
        #expect(grid.columnCount(for: width, itemCount: items) == expected)
    }

    @Test func adaptiveGridColumnWidthFillsRow() {
        let grid = AdaptiveGrid(minColumnWidth: 200, spacing: 12)
        #expect(grid.columnWidth(for: 1012, columns: 4) == 244)
        #expect(grid.columnWidth(for: .infinity, columns: 1) == 200)
    }

    @Test func adaptiveGridRowsTakeTallestItem() {
        #expect(AdaptiveGrid.rowHeights(itemHeights: [10, 30, 20, 5, 7], columns: 2) == [30, 20, 7])
        #expect(AdaptiveGrid.rowHeights(itemHeights: [], columns: 3).isEmpty)
    }
}
