import Foundation

/// Whether two records are the same workout (MVP2-107), for a calendar import's placeholder
/// activities: when one is already stored (an activity the file repeats, or a real workout already
/// imported from HealthKit), and when HealthKit's import meets a placeholder made from a file.
///
/// A rule on what the two share, not an id: the same sport, a start within five minutes (two devices
/// start a workout a few seconds apart) and a duration within a fifth (or two minutes, if longer).
enum PlaceholderActivityMatching {
    /// The most the starts may differ, in seconds.
    static let startTolerance: TimeInterval = 300
    /// The least the durations may be allowed to differ by, in seconds.
    static let minimumDurationTolerance: TimeInterval = 120

    /// Whether a workout of `sport` starting at `start` for `duration` is the same as `item`.
    static func isSameWorkout(sport: Sport, start: Date, duration: TimeInterval, as item: ActivityListItem) -> Bool {
        guard sport.isSameFamily(as: item.sport),
              abs(start.timeIntervalSince(item.start)) <= startTolerance
        else { return false }
        let tolerance = max(minimumDurationTolerance, 0.2 * max(duration, item.duration))
        return abs(duration - item.duration) <= tolerance
    }
}
