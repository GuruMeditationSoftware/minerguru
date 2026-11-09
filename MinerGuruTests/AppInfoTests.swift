import Foundation
import Testing
@testable import MinerGuru

@Suite("App info")
struct AppInfoTests {
    @Test func licenseMatchesTheFileInTheRepository() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("LICENSE.txt"), encoding: .utf8)
        #expect(file.trimmingCharacters(in: .newlines) == AppInfo.licenseText)
    }
}
