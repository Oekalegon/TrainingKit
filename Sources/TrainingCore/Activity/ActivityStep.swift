import Foundation

/// One step of a plan-started workout as the Apple Watch recorded it (MVP2-146): when it began and
/// ended, and what HealthKit summarised for it.
///
/// Where a step's figures come from: a workout started from a scheduled plan is saved with one
/// `HKWorkoutActivity` per step (a repeat is one per repetition and step), each with exact times, the
/// step's own key path and statistics. `HealthKitActivityImporter` reads those; a workout that wasn't
/// started from a plan has none, and its ``Activity/steps`` is empty. Use ``ActivityStepAligner`` to
/// lay them over the plan's steps.
///
/// Every figure but the times is optional: a step may have recorded no distance (a treadmill run, or
/// distance access not allowed to the app) or no heart rate.
public struct ActivityStep: Sendable, Codable, Hashable {
    /// The block this step belongs to, as the Watch numbers them: 0 is the warm-up, the plan's blocks
    /// follow, and the cool-down is last. See ``ActivityStepAligner``.
    public let block: Int
    /// Which repetition of the block, from 0.
    public let repetition: Int
    /// The step's position within the block, from 0.
    public let step: Int
    /// When the step began.
    public let start: Date
    /// When the step ended: the next step begins here.
    public let end: Date
    /// The time spent in the step with the workout running, in seconds: `end - start` less any pause.
    public let duration: TimeInterval
    /// Distance covered in the step, in meters, if it recorded one.
    public let distanceMeters: Double?
    /// Average heart rate over the step, in beats per minute, if it recorded one.
    public let averageHeartRateBPM: Double?
    /// Elevation climbed in the step, in meters, if it recorded one.
    public let elevationAscendedMeters: Double?
    /// Whether the Watch counted the step's goal as met (`WOIntervalStepSuccessful`); `nil` when it
    /// didn't say, as it doesn't for a cool-down.
    public let wasGoalMet: Bool?

    /// Average pace over the step, in seconds per kilometer: ``duration`` over ``distanceMeters``.
    /// `nil` without a distance, or for one too short to give a meaningful pace.
    public var averagePaceSecondsPerKilometer: Double? {
        guard let distanceMeters, distanceMeters >= 1, duration > 0 else { return nil }
        return duration / distanceMeters * 1000
    }

    /// Creates a step.
    ///
    /// - Parameters:
    ///   - block: The Watch's block number: 0 is the warm-up.
    ///   - repetition: Which repetition of the block, from 0.
    ///   - step: The step's position within the block, from 0.
    ///   - start: When the step began.
    ///   - end: When the step ended.
    ///   - duration: Seconds spent with the workout running; defaults to `end - start`.
    ///   - distanceMeters: Distance covered, if recorded.
    ///   - averageHeartRateBPM: Average heart rate, if recorded.
    ///   - elevationAscendedMeters: Elevation climbed, if recorded.
    ///   - wasGoalMet: Whether the Watch counted the goal as met, if it said.
    public init(
        block: Int, repetition: Int, step: Int, start: Date, end: Date, duration: TimeInterval? = nil,
        distanceMeters: Double? = nil, averageHeartRateBPM: Double? = nil,
        elevationAscendedMeters: Double? = nil, wasGoalMet: Bool? = nil
    ) {
        self.block = block
        self.repetition = repetition
        self.step = step
        self.start = start
        self.end = end
        self.duration = duration ?? end.timeIntervalSince(start)
        self.distanceMeters = distanceMeters
        self.averageHeartRateBPM = averageHeartRateBPM
        self.elevationAscendedMeters = elevationAscendedMeters
        self.wasGoalMet = wasGoalMet
    }

    /// Parses the Watch's step key path, `block.repetition.step` (e.g. `"2.3.1"`, from zero), the
    /// value of `WOIntervalStepKeyPath` in a workout activity's metadata.
    ///
    /// - Parameter keyPath: The key path text.
    /// - Returns: The three numbers, or `nil` if it isn't three non-negative integers.
    public static func components(ofKeyPath keyPath: String) -> (block: Int, repetition: Int, step: Int)? {
        let parts = keyPath.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let block = parts[0], let repetition = parts[1], let step = parts[2],
              block >= 0, repetition >= 0, step >= 0
        else { return nil }
        return (block, repetition, step)
    }
}
