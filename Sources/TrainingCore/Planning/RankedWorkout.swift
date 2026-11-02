import Foundation

/// A template with its parameters filled in, as ``WorkoutRanker`` offers it for a day (MVP5-155).
///
/// The same template can come back several times with different values: a 30 and a 35 minute easy run
/// are two ranked workouts.
public struct RankedWorkout: Identifiable, Sendable, Hashable {
    /// The workout's own id.
    public var id: UUID { workout.id }
    /// The template the workout was made from.
    public let template: WorkoutTemplate
    /// The parameter values, one per parameter of the template, on the steps of ``ParameterGrid``.
    public let values: [String: Double]
    /// The template filled in with ``values``.
    public let workout: StructuredWorkout
    /// The planned duration, in seconds.
    public let seconds: TimeInterval
    /// The estimated load, in TRIMP.
    public let load: Double
    /// The TSB at the end of the day's micro with the workout in the plan, or `nil` when the day is in no micro
    /// or the series does not reach it.
    public let endOfMicroTSB: Double?
    /// The planned time of the day's micro with the workout in the plan, in seconds; `nil` when the day is in no micro.
    public let microSeconds: TimeInterval?
    /// Why the workout ranks lower, empty when nothing counts against it. Most telling first.
    public let reasons: [WorkoutRankReason]

    /// Creates a ranked workout.
    ///
    /// - Parameters:
    ///   - template: The template.
    ///   - values: The parameter values.
    ///   - workout: The filled-in template.
    ///   - seconds: The planned duration.
    ///   - load: The estimated load.
    ///   - endOfMicroTSB: The TSB at the end of the micro with the workout.
    ///   - microSeconds: The micro's planned time with the workout.
    ///   - reasons: What counts against the workout.
    public init(
        template: WorkoutTemplate, values: [String: Double], workout: StructuredWorkout, seconds: TimeInterval, load: Double,
        endOfMicroTSB: Double?, microSeconds: TimeInterval?, reasons: [WorkoutRankReason]
    ) {
        self.template = template
        self.values = values
        self.workout = workout
        self.seconds = seconds
        self.load = load
        self.endOfMicroTSB = endOfMicroTSB
        self.microSeconds = microSeconds
        self.reasons = reasons
    }
}
