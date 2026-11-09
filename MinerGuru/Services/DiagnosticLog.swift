import Foundation

/// A small local log for finding problems after days of real use: states, alerts, writes to miners and
/// regular measurements. It leaves the device only when the user exports it, so it holds no passwords,
/// wallet addresses, pool users, one-time codes or names, only the miners' addresses on the local network.
final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()
    /// Two files of this size at most: the current one and the one before it.
    static let maxBytes = 1_000_000

    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()
    private var path: URL?

    init(path: URL? = nil) {
        self.path = path
    }

    /// The running app turns the log on; tests and previews write nothing.
    func activate(path: URL = DiagnosticLog.defaultPath) {
        lock.withLock { self.path = path }
    }

    static var defaultPath: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "MinerGuru").appendingPathComponent("minerguru.log")
    }

    private static func olderPath(_ path: URL) -> URL {
        path.deletingLastPathComponent().appendingPathComponent("minerguru.1.log")
    }

    func write(_ category: String, _ message: String, at date: Date = Date()) {
        lock.withLock {
            guard let path else { return }
            let text = message.replacingOccurrences(of: "\n", with: " ")
            let line = Data("\(formatter.string(from: date)) [\(category)] \(text)\n".utf8)
            let manager = FileManager.default
            try? manager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: path.path))?[.size] as? Int, size + line.count > Self.maxBytes {
                try? manager.removeItem(at: Self.olderPath(path))
                try? manager.moveItem(at: path, to: Self.olderPath(path))
            }
            guard let handle = try? FileHandle(forWritingTo: path) else {
                try? line.write(to: path)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    /// Everything still on disk, oldest first.
    func exportText() -> String {
        lock.withLock {
            guard let path else { return "" }
            return [Self.olderPath(path), path].compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
        }
    }

    /// Model, firmware and the names (never the values) of the fields a miner reports.
    static func profile(_ miner: MinerDevice, _ info: MinerSystemInfo) -> String {
        var keys: [String] = []
        if let data = miner.rawJSON?.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            keys = object.keys.sorted()
        }
        return "model=\(info.detectedHardwareTitle) firmware=\(info.firmwareVersion) axeos=\(info.axeOSVersion ?? "-") keys=\(keys.joined(separator: ","))"
    }
}
