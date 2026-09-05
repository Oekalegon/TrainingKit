import Foundation

/// Turns a distance into a duration at a given heart-rate zone.
///
/// Used to estimate how long a `.distance` ``WorkoutStep`` will take, so its expected load can be
/// computed alongside `.time` steps. Pace is expressed relative to a threshold pace (roughly
/// zone 4) using a per-zone multiplier table; multipliers greater than 1 are slower than
/// threshold, less than 1 are faster.
public struct PaceModel: Sendable, Codable {
    /// Threshold pace, in seconds per kilometer.
    public var thresholdPaceSecondsPerKilometer: Double

    /// Per-zone pace multiplier relative to threshold pace. Missing zones fall back to 1.0.
    public var zonePaceMultipliers: [Int: Double]

    public init(
        thresholdPaceSecondsPerKilometer: Double,
        zonePaceMultipliers: [Int: Double] = [1: 1.35, 2: 1.20, 3: 1.08, 4: 1.0, 5: 0.92]
    ) {
        self.thresholdPaceSecondsPerKilometer = thresholdPaceSecondsPerKilometer
        self.zonePaceMultipliers = zonePaceMultipliers
    }

    /// Seconds required to cover one meter at the given heart-rate zone.
    public func secondsPerMeter(atZone zone: Int) -> Double {
        let multiplier = zonePaceMultipliers[zone] ?? 1.0
        return (thresholdPaceSecondsPerKilometer * multiplier) / 1000
    }

    /// The estimated duration to cover `meters` at the given heart-rate zone.
    public func duration(forMeters meters: Double, atZone zone: Int) -> TimeInterval {
        meters * secondsPerMeter(atZone: zone)
    }
}
