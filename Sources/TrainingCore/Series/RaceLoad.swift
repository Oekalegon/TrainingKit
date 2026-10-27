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
    /// A pace target gives the step its duration (distance times pace) and, as its intensity, the
    /// heart-rate zone whose pace in the athlete's pace model is nearest the goal pace (with the pace
    /// as the companion target), so a 100 km at an easy pace weighs what easy running weighs, not
    /// what the estimator assumes for every pace target (zone 4). A heart-rate range and a perceived
    /// effort become the matching targets over the distance, which the estimator times at the
    /// athlete's pace model. Without a target, or with a predicted one, the step is the distance with
    /// no target.
    static func workout(for race: Race, athlete: AthleteProfile) -> StructuredWorkout {
        let goal: StepGoal
        let target: IntensityTarget?
        var companion: IntensityTarget?
        switch race.specificPhaseTarget {
        case .pace(let secondsPerKilometer):
            goal = .time(race.distanceMeters / 1000 * secondsPerKilometer)
            target = .heartRateZone(nearestZone(toSecondsPerKilometer: secondsPerKilometer, athlete: athlete))
            companion = .pace(secondsPerKilometer...secondsPerKilometer)
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
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: goal, target: target, companionTarget: companion)])],
            sessionType: .race
        )
    }

    /// The zone (1 to 5) whose pace in the pace model is nearest `secondsPerKilometer`, by ratio.
    private static func nearestZone(toSecondsPerKilometer secondsPerKilometer: Double, athlete: AthleteProfile) -> Int {
        (1...5).min { lhs, rhs in
            abs(log(athlete.paceModel.secondsPerMeter(atZone: lhs) * 1000 / secondsPerKilometer))
                < abs(log(athlete.paceModel.secondsPerMeter(atZone: rhs) * 1000 / secondsPerKilometer))
        } ?? 3
    }
}
