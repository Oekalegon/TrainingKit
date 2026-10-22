import Foundation

/// Why ``PlanGenerator`` could not build a plan at all (MVP5-145).
///
/// These are the failures that leave nothing to propose. Everything the generator can still work
/// around (a session with no day, a profile with no template, a phase that did not fit) is a
/// ``PlanCompromise`` on the returned ``PlanProposal`` instead.
public enum PlanGeneratorError: Error, Sendable, Equatable {
    /// The lead time cannot hold the paradigm's taper and shortest specific phase, or the micro
    /// length or lead time is invalid; see ``LeadTimeCompromiser/adjust(_:paradigm:leadTimeDays:microLengthDays:preferences:)``.
    case leadTime(LeadTimeError)
    /// The layout has no micro: the race is before the start, or the macro template has no usable block.
    case noLayout
    /// The starting and peak volume or the maximum weekly volume do not form a curve; see
    /// ``VolumeCurveBuilder/targets(for:starting:peak:)``. A ``PlanPreferences/maxWeeklyVolume``
    /// in another measure than the requested volume is ``VolumeCurveError/mismatchedMeasure``.
    case volumeCurve(VolumeCurveError)
    /// The volume is not in ``VolumeMeasure/durationSeconds``; the generator sizes sessions in seconds
    /// and has no conversion from distance or TRIMP.
    case unsupportedVolumeMeasure(VolumeMeasure)
    /// A template the fitter chose could not be instantiated.
    case workoutTemplate(WorkoutTemplateError)
}
