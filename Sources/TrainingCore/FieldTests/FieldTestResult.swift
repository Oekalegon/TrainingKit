import Foundation

/// What a field test measured (MVP2-154), offered to the athlete to confirm before it changes their
/// heart-rate settings.
///
/// Produced by ``FieldTestMeasurer`` and ``TrainingModel/fieldTestResult(forActivity:measurer:)``, applied (after
/// the athlete confirms) with ``TrainingModel/applyFieldTestResult(_:asOf:)``. Unlike
/// ``MaxHeartRateSuggestion``, a max heart rate result may be lower than the value on record: a test
/// is a deliberate attempt at the maximum, so falling short of the old value is information.
public struct FieldTestResult: Sendable, Hashable {
    /// Which setting the test measured.
    public enum Measurement: Sendable, Hashable {
        /// The highest heart rate held for a few seconds, from a ``WorkoutPurpose/maxHRTest``.
        case maxHeartRate
        /// The average heart rate over the last 20 minutes of the 30-minute effort, from a
        /// ``WorkoutPurpose/lthrTest``.
        case lactateThresholdHeartRate
    }

    /// Which setting the test measured.
    public let measurement: Measurement
    /// The ``Activity`` the test was recorded in.
    public let activityID: UUID
    /// The activity's start, which also becomes the new setting's effective date.
    public let activityStart: Date
    /// The measured value, rounded to a whole beat per minute.
    public let valueBPM: Double
    /// The value in effect at ``activityStart`` for this setting, in beats per minute, or `nil` when
    /// none was recorded (a lactate threshold the athlete never entered).
    public let currentBPM: Double?
    /// Whether the test's effort was located from the plan rather than from the steps the Watch
    /// recorded: the activity wasn't started from the scheduled workout, so the effort is assumed to
    /// have followed the plan's timing (and be within 5% of its length). Always `false` for a max heart rate test, which looks at the
    /// whole activity. A host app may want to ask the athlete to check such a result.
    public let isEstimatedFromPlan: Bool

    /// Whether the value on record comes from a more reliable source than a field test (a lab test), so
    /// applying the result would replace a better measurement with a worse one. A host app should say so
    /// when it asks the athlete, or default to keeping the old value. See ``MaxHeartRateSource/reliabilityRank``.
    public let replacesMoreReliableSource: Bool

    /// Whether the value differs from ``currentBPM``. A host app can use it to say "no change", but applying
    /// an equal value still records the new source (a measured max replaces a formula's), so don't skip
    /// ``TrainingModel/applyFieldTestResult(_:asOf:)`` for a result whose value matches if the athlete should
    /// get the measured source.
    public var changesValue: Bool { currentBPM != valueBPM }

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - measurement: Which setting the test measured.
    ///   - activityID: The activity the test was recorded in.
    ///   - activityStart: The activity's start.
    ///   - valueBPM: The measured value, in beats per minute.
    ///   - currentBPM: The value in effect at `activityStart`, if any.
    ///   - isEstimatedFromPlan: Whether the effort was located from the plan; defaults to `false`.
    ///   - replacesMoreReliableSource: Whether the value on record is from a more reliable source than
    ///     a field test; defaults to `false`.
    public init(
        measurement: Measurement, activityID: UUID, activityStart: Date, valueBPM: Double,
        currentBPM: Double?, isEstimatedFromPlan: Bool = false, replacesMoreReliableSource: Bool = false
    ) {
        self.measurement = measurement
        self.activityID = activityID
        self.activityStart = activityStart
        self.valueBPM = valueBPM
        self.currentBPM = currentBPM
        self.isEstimatedFromPlan = isEstimatedFromPlan
        self.replacesMoreReliableSource = replacesMoreReliableSource
    }
}
