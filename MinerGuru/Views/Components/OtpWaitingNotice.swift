import SwiftUI

/// Schedules skip miners that have no valid session: this names them and lets the user enter a code.
struct OtpWaitingNotice: View {
    @ObservedObject var store: MinerStore
    @ObservedObject private var otp: OtpSessions
    @State private var problem: String?

    init(store: MinerStore) {
        self.store = store
        self._otp = ObservedObject(wrappedValue: store.otp)
    }

    var body: some View {
        let waiting = store.minersAwaitingOtp
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Zeitpläne laufen auf diesen Minern nur mit gültiger Sitzung (bis zu 24 Stunden).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(waiting) { miner in
                    HStack {
                        Label(miner.displayName, systemImage: "lock")
                        Spacer()
                        Button("Code eingeben") { enterCode(for: miner) }
                    }
                }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(Signal.bad)
                }
            }
        }
    }

    private func enterCode(for miner: MinerDevice) {
        Task {
            do {
                try await otp.authorize(miner)
                problem = nil
            } catch OtpError.cancelled {
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
