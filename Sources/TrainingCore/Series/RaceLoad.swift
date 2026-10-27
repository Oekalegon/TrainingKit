import Foundation

/// The load a race adds on its day, for ``DailyLoadSeries``.
///
/// A race is not a ``PlannedActivity``, so it has no workout to estimate. This builds the one-step
/// workout the race stands for and hands it to the same ``PlannedLoadEstimator`` as a planned run, so
/// a 100 km race weighs what 100 km of running at that effort weighs.
enum RaceLoad {
    /// The load of `race`: its ``Race/expectedLoadOverride`` if set, else the estimator's value for
    /// ``workout(for:athlete:)``.
    static func load(for race: Race, estimator: PlannedLoadEstimator, athlete: AthleteProfile) -> Double {
        race.expectedLoadOverride ?? estimator.estimatedLoad(for: workout(for: race, athlete: athlete), athlete: athlete).value
    }

    /// One work step over the race distance, aimed at the race's ``Race/specificPhaseTarget``.
    ///
    /// A pace target gives the step its duration (distance times pace) and a pace target; a heart-rate
    /// range and a perceived effort become the matching targets over the distance, which the estimator
    /// times at the athlete's pace model. Without a target, or with a predicted one, the step is the
    /// distance with no target.
    static func workout(for race: Race, athlete: AthleteProfile) -> StructuredWorkout {
        let goal: StepGoal
        let target: IntensityTarget?
        switch race.specificPhaseTarget {
        case .pace(let secondsPerKilometer):
            goal = .time(race.distanceMeters / 1000 * secondsPerKilometer)
            target = .pace(secondsPerKilometer...secondsPerKilometer)
        case .heartRate(let range):
            goal = .distance(race.distanceMeters)
            target = .heartRateRange(range.lowerBound, range.upperBound)
        case .perceivedEffort(let rating):
            goal = .distance(race.distanceMeters)
            target = .rpe(rating)
        case .predictedFromFitness, nil:
            goal = .distance(race.distanceMeters)
            target = nil
        }
        return StructuredWorkout(
            name: race.name,
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: goal, target: target)])],
            sessionType: .race
        )
    }
}
