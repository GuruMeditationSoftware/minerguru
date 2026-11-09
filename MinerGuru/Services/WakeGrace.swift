import Foundation

/// Tells a miner that went away apart from a Mac that just woke. Right after sleep, even a short Power Nap
/// wake for maintenance, the network needs a few seconds, and a request sent before sleep times out on
/// waking. Every miner then looks offline for one poll, although none of them was.
///
/// Sleep shows as the gap between a clock that keeps running in sleep and one that stops.
struct WakeGrace {
    /// How long after a wake a failed poll does not count.
    static let duration: TimeInterval = 30
    /// A smaller gap between the two clocks is timer noise, not sleep.
    static let minimumSleep: TimeInterval = 2

    private var last: (wall: TimeInterval, awake: TimeInterval)?
    private var until: TimeInterval?

    /// Feed both clocks in seconds: `wall` keeps running in sleep, `awake` stops.
    /// Returns how long the Mac slept since the last call, or nil if it did not.
    mutating func observe(wall: TimeInterval, awake: TimeInterval) -> TimeInterval? {
        defer { last = (wall, awake) }
        guard let last else { return nil }
        let slept = (wall - last.wall) - (awake - last.awake)
        guard slept >= Self.minimumSleep else { return nil }
        until = wall + Self.duration
        return slept
    }

    /// Whether a failed poll at this moment comes too soon after a wake to mean anything.
    func isActive(wall: TimeInterval) -> Bool {
        until.map { wall < $0 } ?? false
    }
}

extension WakeGrace {
    private static let wallStart = ContinuousClock.now
    private static let awakeStart = SuspendingClock.now

    /// Seconds on a clock that keeps running while the Mac sleeps.
    static var wallSeconds: TimeInterval { seconds(ContinuousClock.now - wallStart) }
    /// Seconds on a clock that stops while the Mac sleeps.
    static var awakeSeconds: TimeInterval { seconds(SuspendingClock.now - awakeStart) }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) * 1e-18
    }
}
