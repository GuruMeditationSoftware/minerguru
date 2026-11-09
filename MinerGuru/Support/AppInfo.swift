import SwiftUI

/// Who made the app, where feedback goes and under which terms it ships. The license is LICENSE.txt, word for word.
enum AppInfo {
    static let madeBy = "Made by GuruMeditation"
    static let feedbackURL = URL(string: "https://github.com/GuruMeditationSoftware/minerguru/issues")!
    static let releasesURL = URL(string: "https://github.com/GuruMeditationSoftware/minerguru/releases/latest")!
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    static var updateCheckURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["MINERGURU_UPDATE_URL"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://api.github.com/repos/GuruMeditationSoftware/minerguru/releases/latest")!
    }

    static let licenseText = """
MIT License

Copyright (c) 2026 GuruMeditation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
}

/// The license in full, with lines joined where they wrap at 80 columns, narrower here. The Mac app bundles no third-party code, so there are no further notices.
struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("License")
                .font(.title3.weight(.medium))
            Text("Open source under the MIT license and free to use. Use and changes to your hardware are at your own risk.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(verbatim: AppInfo.licenseText.replacingOccurrences(of: #"(?m)^(.{60,})\n *(?=\S)"#, with: "$1 ", options: .regularExpression))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
