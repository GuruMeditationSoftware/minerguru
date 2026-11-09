import Foundation
import AppKit

/// Severity level parsed from ESP-IDF / AxeOS / NerdOS log output.
enum MinerLogLevel: String, CaseIterable, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"

    var shortLabel: String {
        switch self {
        case .info: return "I"
        case .warning: return "W"
        case .error: return "E"
        case .debug: return "D"
        }
    }
}

/// Filter categories for the live miner log viewer.
enum MinerLogCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case sharesAndPool
    case asicAndHardware
    case powerAndThermal
    case warningsAndErrors
    case systemAndNetwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .sharesAndPool: return "Shares & Pool"
        case .asicAndHardware: return "ASIC & Hardware"
        case .powerAndThermal: return String(localized: "Power & Cooling")
        case .warningsAndErrors: return String(localized: "Warnings & Errors")
        case .systemAndNetwork: return String(localized: "System & Network")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet.rectangle"
        case .sharesAndPool: return "checkmark.seal"
        case .asicAndHardware: return "cpu"
        case .powerAndThermal: return "thermometer.medium"
        case .warningsAndErrors: return "exclamationmark.triangle"
        case .systemAndNetwork: return "wifi"
        }
    }
}

/// A single structured log line from a Bitaxe or NerdQAxe++ miner.
struct MinerLogEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let receivedAt: Date
    let espTimestamp: String?
    let level: MinerLogLevel
    let componentTag: String?
    let message: String
    let rawLine: String
    let isShareAccepted: Bool
    let isShareRejected: Bool

    init(
        id: UUID = UUID(),
        receivedAt: Date = Date(),
        espTimestamp: String?,
        level: MinerLogLevel,
        componentTag: String?,
        message: String,
        rawLine: String,
        isShareAccepted: Bool,
        isShareRejected: Bool
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.espTimestamp = espTimestamp
        self.level = level
        self.componentTag = componentTag
        self.message = message
        self.rawLine = rawLine
        self.isShareAccepted = isShareAccepted
        self.isShareRejected = isShareRejected
    }

    /// ESP-IDF log format: `I (123456) component_tag: message` or `I (12:34:56.789) tag: message`.
    // The pattern is a literal; failing to compile it is a programming error.
    private static let espLogPattern = try! NSRegularExpression(pattern: #"^([IWEDV])\s*\(([^)]+)\)\s*([^:]+):\s*(.*)$"#)

    /// Parses a raw line from `ws://<ip>/api/ws`, stripping ANSI color codes and extracting ESP-IDF metadata.
    static func parse(rawLine: String, receivedAt: Date = Date()) -> MinerLogEntry? {
        let cleaned = stripANSICodes(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        var level: MinerLogLevel = .info
        var espTimestamp: String? = nil
        var componentTag: String? = nil
        var messageBody = cleaned

        if let match = Self.espLogPattern.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           match.numberOfRanges == 5 {

            if let r1 = Range(match.range(at: 1), in: cleaned) {
                let lvlChar = String(cleaned[r1])
                switch lvlChar {
                case "W": level = .warning
                case "E": level = .error
                case "D", "V": level = .debug
                default: level = .info
                }
            }
            if let r2 = Range(match.range(at: 2), in: cleaned) {
                espTimestamp = String(cleaned[r2]).trimmingCharacters(in: .whitespaces)
            }
            if let r3 = Range(match.range(at: 3), in: cleaned) {
                componentTag = String(cleaned[r3]).trimmingCharacters(in: .whitespaces)
            }
            if let r4 = Range(match.range(at: 4), in: cleaned) {
                messageBody = String(cleaned[r4]).trimmingCharacters(in: .whitespaces)
            }
        } else {
            // Secondary heuristic if non-standard log line
            let lower = cleaned.lowercased()
            if lower.contains("error") || lower.contains("failed") || lower.contains("rejected") {
                level = .error
            } else if lower.contains("warn") || lower.contains("overheat") {
                level = .warning
            }
        }

        let lowerMsg = messageBody.lowercased()
        let lowerTag = (componentTag ?? "").lowercased()

        let isAccepted = lowerMsg.contains("accepted")
            || lowerMsg.contains("share accepted")
            || (lowerTag.contains("stratum") && lowerMsg.contains("result: true"))

        let isRejected = lowerMsg.contains("rejected")
            || lowerMsg.contains("share rejected")
            || (lowerTag.contains("stratum") && lowerMsg.contains("result: false"))

        if isRejected && level == .info {
            level = .warning
        }

        return MinerLogEntry(
            receivedAt: receivedAt,
            espTimestamp: espTimestamp,
            level: level,
            componentTag: componentTag,
            message: messageBody.isEmpty ? cleaned : messageBody,
            rawLine: cleaned,
            isShareAccepted: isAccepted,
            isShareRejected: isRejected
        )
    }

    /// Removes ANSI escape sequences (`\x1B[...m` as well as orphaned `[0;32m` / `[0m` sequences).
    static func stripANSICodes(from input: String) -> String {
        // 1. Standard ESC [ ... m sequences
        var result = input.replacingOccurrences(
            of: #"\u001B\[[0-9;]*[a-zA-Z]"#,
            with: "",
            options: .regularExpression
        )
        // 2. Orphaned bracket color codes sometimes emitted by ESP-Miner WebSocket logger
        result = result.replacingOccurrences(
            of: #"\[([0-9]{1,2};)?[0-9]{1,2}m"#,
            with: "",
            options: .regularExpression
        )
        return result
    }

    /// Checks whether this log entry matches the selected category filter.
    func matches(category: MinerLogCategoryFilter) -> Bool {
        switch category {
        case .all:
            return true
        case .warningsAndErrors:
            return level == .warning || level == .error || isShareRejected
        case .sharesAndPool:
            let haystack = "\(componentTag ?? "") \(message)".lowercased()
            return isShareAccepted
                || isShareRejected
                || haystack.contains("stratum")
                || haystack.contains("pool")
                || haystack.contains("share")
                || haystack.contains("mining.")
                || haystack.contains("job")
                || haystack.contains("work")
                || haystack.contains("diff")
                || haystack.contains("extranonce")
        case .asicAndHardware:
            let haystack = "\(componentTag ?? "") \(message)".lowercased()
            return haystack.contains("asic")
                || haystack.contains("bm13")
                || haystack.contains("nonce")
                || haystack.contains("chip")
                || haystack.contains("freq")
                || haystack.contains("hashrate")
                || haystack.contains("serial")
        case .powerAndThermal:
            let haystack = "\(componentTag ?? "") \(message)".lowercased()
            return haystack.contains("power")
                || haystack.contains("temp")
                || haystack.contains("fan")
                || haystack.contains("thermal")
                || haystack.contains("vcore")
                || haystack.contains("voltage")
                || haystack.contains("current")
                || haystack.contains("ina260")
                || haystack.contains("emc210")
                || haystack.contains("pid")
        case .systemAndNetwork:
            let haystack = "\(componentTag ?? "") \(message)".lowercased()
            return haystack.contains("wifi")
                || haystack.contains("http")
                || haystack.contains("ws")
                || haystack.contains("system")
                || haystack.contains("nvs")
                || haystack.contains("heap")
                || haystack.contains("ota")
                || haystack.contains("net")
        }
    }

    /// Checks whether this entry matches the user's search query.
    func matches(searchText: String) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if message.localizedCaseInsensitiveContains(trimmed) { return true }
        if let tag = componentTag, tag.localizedCaseInsensitiveContains(trimmed) { return true }
        if level.rawValue.localizedCaseInsensitiveContains(trimmed) { return true }
        return false
    }

    /// Formatted plain-text line for clipboard copy & file export.
    func formattedExportLine(dateFormatter: DateFormatter) -> String {
        let timeStr = dateFormatter.string(from: receivedAt)
        let tagStr = componentTag.map { "[\($0)] " } ?? ""
        let espStr = espTimestamp.map { "(\($0)) " } ?? ""
        return "\(timeStr) [\(level.shortLabel)] \(espStr)\(tagStr)\(message)"
    }
}

/// Manages a live WebSocket log stream (`ws://<host>/api/ws`) for a single Bitaxe or NerdQAxe++ miner.
@MainActor
final class MinerLogStreamController: ObservableObject {
    enum StreamState: Equatable {
        case stopped
        case connecting
        case streaming
        case paused
        case error(String)
    }

    @Published private(set) var entries: [MinerLogEntry] = []
    @Published private(set) var state: StreamState = .stopped
    @Published var categoryFilter: MinerLogCategoryFilter = .all
    @Published var searchText: String = ""
    @Published var autoScroll: Bool = true
    @Published private(set) var totalLinesReceived: Int = 0
    /// Called with every batch of newly parsed entries (used for the share difficulty chart).
    var onEntries: (([MinerLogEntry]) -> Void)?

    let maxBufferEntries: Int = 1_500

    private var currentHost: String = ""
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var urlSession: URLSession?

    private static let exportDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    init() {}

    var isRunning: Bool {
        state == .streaming || state == .connecting
    }

    /// Filtered entries matching both `categoryFilter` and `searchText`.
    var filteredEntries: [MinerLogEntry] {
        entries.filter { entry in
            entry.matches(category: categoryFilter) && entry.matches(searchText: searchText)
        }
    }

    /// Suggested file name for a log export, e.g. `MinerGuru-Wohnzimmer-Bitaxe-192.168.1.28-2026-10-17_22-30-00.log`.
    nonisolated static func exportFileName(minerName: String, ipAddress: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let safeName = minerName
            .components(separatedBy: CharacterSet(charactersIn: " /:\\"))
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "MinerGuru-\(safeName)-\(ipAddress)-\(formatter.string(from: date)).log"
    }

    /// Starts streaming live logs from `ws://<host>/api/ws`.
    func startStreaming(host: String) {
        let normalized = MinerAPIClient.normalizeHost(host)
        guard !normalized.isEmpty else {
            state = .error(String(localized: "Invalid IP address"))
            return
        }

        // If switching to a different miner, clear previous miner's log buffer
        if currentHost != normalized {
            entries.removeAll()
            totalLinesReceived = 0
            currentHost = normalized
        }

        disconnectSocketOnly()

        guard let wsURL = URL(string: "ws://\(normalized)/api/ws") else {
            state = .error(String(localized: "Invalid WebSocket URL"))
            return
        }

        state = .connecting

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        self.urlSession = session

        let task = session.webSocketTask(with: wsURL)
        self.webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task, host: normalized)
        }
    }

    /// Pauses live log ingestion and closes the WebSocket connection so the ESP32 is not loaded while paused,
    /// while preserving all captured log entries in the viewer for searching/filtering/exporting.
    func pauseStreaming() {
        disconnectSocketOnly()
        state = .paused
    }

    /// Stops streaming completely.
    func stopStreaming() {
        disconnectSocketOnly()
        state = .stopped
    }

    /// Clears all buffered log entries.
    func clearLogs() {
        entries.removeAll()
        totalLinesReceived = 0
    }

    /// Formats all currently filtered entries as plain text for export or clipboard.
    func exportText(minerName: String, ipAddress: String, hardware: String) -> String {
        var lines: [String] = []
        lines.append("# MinerGuru Live-Log Export")
        lines.append("# Miner: \(minerName) (\(ipAddress)) — \(hardware)")
        lines.append(String(localized: "# Exported: \(Self.exportDateFormatter.string(from: Date()))"))
        lines.append("# Filter: \(categoryFilter.title)" + (searchText.isEmpty ? "" : String(localized: " | Search: '\(searchText)'")))
        lines.append(String(localized: "# Lines: \(filteredEntries.count) (of \(entries.count) in buffer)"))
        lines.append(String(repeating: "-", count: 78))

        for entry in filteredEntries {
            lines.append(entry.formattedExportLine(dateFormatter: Self.exportDateFormatter))
        }
        return lines.joined(separator: "\n")
    }

    private func disconnectSocketOnly() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    private func receiveLoop(task: URLSessionWebSocketTask, host: String) async {
        var didConfirmStream = false

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if Task.isCancelled { break }

                if !didConfirmStream {
                    didConfirmStream = true
                    state = .streaming
                }

                let rawText: String
                switch message {
                case .string(let str):
                    rawText = str
                case .data(let data):
                    rawText = String(decoding: data, as: UTF8.self)
                @unknown default:
                    rawText = ""
                }

                if !rawText.isEmpty {
                    appendRawChunk(rawText)
                }
            } catch {
                if Task.isCancelled { break }
                // If user already paused or stopped, ignore cancellation error
                if state == .paused || state == .stopped {
                    break
                }
                state = .error(String(localized: "Connection to ws://\(host)/api/ws lost (\(error.localizedDescription))"))
                break
            }
        }
    }

    private func appendRawChunk(_ chunk: String) {
        let now = Date()
        let rawLines = chunk.components(separatedBy: .newlines)
        var parsedBatch: [MinerLogEntry] = []

        for rawLine in rawLines {
            if let entry = MinerLogEntry.parse(rawLine: rawLine, receivedAt: now) {
                parsedBatch.append(entry)
            }
        }

        guard !parsedBatch.isEmpty else { return }

        totalLinesReceived += parsedBatch.count
        onEntries?(parsedBatch)
        entries.append(contentsOf: parsedBatch)

        if entries.count > maxBufferEntries {
            let overflow = entries.count - maxBufferEntries
            entries.removeFirst(overflow)
        }
    }
}
