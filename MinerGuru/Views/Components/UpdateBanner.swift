import SwiftUI

/// Tells the user on the overview that a newer version exists, until they dismiss it or update.
struct UpdateBanner: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        if let version = updates.bannerVersion {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Accent.color)
                Text("MinerGuru \(version) ist verfügbar")
                Spacer()
                Link("Zum Download", destination: AppInfo.releasesURL)
                Button {
                    updates.dismissBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Ausblenden")
                .accessibilityLabel("Ausblenden")
            }
            .font(.callout)
            .panel(padding: 12)
        }
    }
}
