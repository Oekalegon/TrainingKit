import Foundation

extension PlannedIntensityClassifier {
    /// The speed level of `workout`: the highest zone among its work steps, however short.
    ///
    /// Warm-up, recovery and cool-down steps are ignored, so 8-second hill sprints with long
    /// recoveries are ``SpeedLevel/max`` although the session's ``IntensityCategory`` is low. A
    /// work step with no target counts as zone 3, like in ``assess(_:athlete:)``; a workout with no
    /// work steps is ``SpeedLevel/slow``.
    ///
    /// - Parameters:
    ///   - workout: The workout to read.
    ///   - athlete: The athlete whose zones and pace model resolve the steps' targets.
    public func speedLevel(of workout: StructuredWorkout, athlete: AthleteProfile) -> SpeedLevel {
        let zone = plannedSteps(workout, athlete: athlete).filter { $0.kind == .work }.map(\.zone).max()
        return zone.map(SpeedLevel.init(zone:)) ?? .slow
    }

    /// `workout` as a ``PlanSession`` on `day`, for the paradigm rules of ``PlanEvaluator``.
    ///
    /// - Parameters:
    ///   - day: The calendar day of the session.
    ///   - workout: The planned workout.
    ///   - athlete: The athlete whose zones and pace model resolve the steps' targets.
    /// - Returns: The session; its ``PlanSession/isLongRun`` is ``StructuredWorkout/isLongRun``, i.e.
    ///   the workout's own ``StructuredWorkout/sessionType`` tag. The day it is planned on, its length and
    ///   the athlete's ``RunAvailability/dayRunTypes`` do not change it.
    public func session(on day: Date, for workout: StructuredWorkout, athlete: AthleteProfile) -> PlanSession {
        PlanSession(
            day: day,
            seconds: plannedSteps(workout, athlete: athlete).reduce(0) { $0 + $1.seconds },
            intensity: assess(workout, athlete: athlete).category,
            speed: speedLevel(of: workout, athlete: athlete),
            isLongRun: workout.isLongRun
        )
    }
}
