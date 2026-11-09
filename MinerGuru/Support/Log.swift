import os

/// Unified logging categories (visible in Console.app, subsystem `app.minerguru.MinerGuru`).
enum Log {
    private static let subsystem = "app.minerguru.MinerGuru"

    static let miner = Logger(subsystem: subsystem, category: "miner")
    static let app = Logger(subsystem: subsystem, category: "app")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let logStream = Logger(subsystem: subsystem, category: "log-stream")
}
