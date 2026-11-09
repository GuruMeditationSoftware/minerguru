import Foundation
import Combine

/// Collects share difficulties for one miner while its detail page is open.
///
/// While the live log is running, every log line is fed in (`ingest`). Otherwise the tracker
/// connects to the log WebSocket once per `sampleInterval` for `sampleWindow` and samples the shares
/// found in that window, so the miner is not loaded with a permanent connection.
@MainActor
final class ShareDifficultyTracker: ObservableObject {
    @Published private(set) var samples: [ShareSample] = []
    @Published private(set) var isSampling = false
    @Published private(set) var lastSampleDate: Date?

    static let sampleInterval: Duration = .seconds(60)
    static let sampleWindow: Duration = .seconds(10)
    static let maxSamples = 600

    private var samplingTask: Task<Void, Never>?

    deinit {
        samplingTask?.cancel()
    }

    /// Adds parsed log entries (from the live log or a sample window).
    func ingest(_ entries: [MinerLogEntry]) {
        let new = entries.compactMap(ShareSample.parse)
        guard !new.isEmpty else { return }
        samples.append(contentsOf: new)
        // Sources can overlap in time (a sample window still finishing when the live log starts).
        if let lastBefore = samples.dropLast(new.count).last, let firstNew = new.first, firstNew.date < lastBefore.date {
            samples.sort { $0.date < $1.date }
        }
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
    }

    /// Starts periodic sampling; skipped while `isLiveLogRunning` reports an active live log.
    func startSampling(host: String, isLiveLogRunning: @escaping @MainActor () -> Bool) {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                if !isLiveLogRunning() {
                    await self?.sampleOnce(host: host, isLiveLogRunning: isLiveLogRunning)
                }
                try? await Task.sleep(for: Self.sampleInterval)
            }
        }
    }

    func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
        isSampling = false
    }

    private func sampleOnce(host: String, isLiveLogRunning: @MainActor () -> Bool) async {
        isSampling = true
        defer { isSampling = false }
        let chunks = await MinerLogSampler.capture(host: host, duration: Self.sampleWindow)
        // If the live log was started meanwhile it already delivered these results.
        guard !Task.isCancelled, !isLiveLogRunning() else { return }
        let entries = chunks.flatMap { chunk in
            chunk.text
                .components(separatedBy: .newlines)
                .compactMap { MinerLogEntry.parse(rawLine: $0, receivedAt: chunk.receivedAt) }
        }
        ingest(entries)
        lastSampleDate = Date()
    }
}

/// Opens the miner's log WebSocket for a short time and returns the received text chunks with their arrival time.
enum MinerLogSampler {
    struct Chunk: Sendable {
        let receivedAt: Date
        let text: String
    }

    static func capture(host: String, duration: Duration) async -> [Chunk] {
        let host = MinerAPIClient.normalizeHost(host)
        guard !host.isEmpty, let url = URL(string: "ws://\(host)/api/ws") else { return [] }

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: url)
        socket.resume()
        defer { session.invalidateAndCancel() }

        // Closing the socket ends the pending receive() below.
        let timer = Task {
            try? await Task.sleep(for: duration)
            socket.cancel(with: .normalClosure, reason: nil)
        }
        defer { timer.cancel() }

        var chunks: [Chunk] = []
        while !Task.isCancelled {
            do {
                switch try await socket.receive() {
                case .string(let text): chunks.append(Chunk(receivedAt: Date(), text: text))
                case .data(let data): chunks.append(Chunk(receivedAt: Date(), text: String(decoding: data, as: UTF8.self)))
                @unknown default: break
                }
            } catch {
                if chunks.isEmpty {
                    Log.logStream.debug("Share sample from \(host, privacy: .public) without data: \(error.localizedDescription, privacy: .public)")
                }
                break
            }
        }
        socket.cancel(with: .normalClosure, reason: nil)
        return chunks
    }
}
