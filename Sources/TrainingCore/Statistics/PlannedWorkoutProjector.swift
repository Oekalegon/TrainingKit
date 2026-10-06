import Foundation

/// Projects the distance/duration/time-in-zone a planned workout would produce, for weekly/period
/// statistics on a day that isn't done yet.
///
/// Walks each step the same way ``TRIMPPlanEstimator`` walks it for load: `.distance` steps
/// contribute their meters directly, `.time`/`.open` steps convert to distance via
/// ``AthleteProfile/paceModel`` at the step's target zone, using
/// ``HeartRateZoneModel/intensityRatio(for:)`` so the assumed intensity always matches the one
/// `TRIMPPlanEstimator` used to estimate the same workout's load.
///
/// Given a non-empty ``PaceHistory``, the steps' paces (and `.open` steps' durations) are forecast
/// from the athlete's earlier, similar workouts by ``HistoricalPaceEstimator`` instead (MVP2-35,
/// MVP2-111). Each step keeps the zone above either way; only the duration of distance and open
/// steps changes, and with it their time in that zone.
struct PlannedWorkoutProjector: Sendable {
    /// Turns a workout step's `StepGoal` into a duration.
    var durationEstimator: WorkoutDurationEstimator

    /// The projected distance/duration/time-in-zone for one workout.
    struct Projection: Sendable {
        let distanceMeters: Double?
        let duration: TimeInterval
        let timeInZone: TimeInZone
        /// How many earlier activities the paces were forecast from; 0 for the pace model alone.
        var matchedActivityCount = 0
    }

    /// One step of a workout, with its projected duration and distance.
    struct StepProjection: Sendable {
        /// Index of the step's block in the workout.
        let block: Int
        /// Which repetition of the block this is, from 1.
        let repetition: Int
        let step: WorkoutStep
        let duration: TimeInterval
        /// The heart-rate zone the step's target falls in, or `nil` when there are no zone settings.
        let zone: Int?
        /// A `distance` step's goal; otherwise projected from the pace model, or `nil` when there are
        /// no heart-rate zone settings to pick a pace by. (``project(workout:athlete:)`` then leaves
        /// the workout's total distance `nil` as a whole.)
        let distanceMeters: Double?
    }

    /// Every step of `workout` with its block repetitions expanded, each with its projected
    /// duration, zone and distance. ``project(workout:athlete:history:before:excluding:)`` sums these.
    ///
    /// - Parameters:
    ///   - workout: The planned workout.
    ///   - athlete: Supplies the zone settings and pace model.
    ///   - history: Earlier activities to forecast paces from; empty for the pace model alone.
    ///   - cutoff: Only activities in `history` that started before this are used.
    ///   - excludedActivityID: An activity in `history` to leave out, e.g. the plan's own.
    func stepProjections(
        workout: StructuredWorkout, athlete: AthleteProfile, history: PaceHistory = .empty,
        before cutoff: Date = .distantFuture, excluding excludedActivityID: UUID? = nil
    ) -> [StepProjection] {
        forecast(workout: workout, athlete: athlete, history: history, before: cutoff, excluding: excludedActivityID).steps
    }

    /// ``HistoricalPaceEstimator``'s forecast when `history` has something to say about `workout`,
    /// else the pace model's projection.
    private func forecast(
        workout: StructuredWorkout, athlete: AthleteProfile, history: PaceHistory,
        before cutoff: Date, excluding excludedActivityID: UUID?
    ) -> (steps: [StepProjection], matchedActivityCount: Int) {
        if !history.observations.isEmpty,
           let historical = HistoricalPaceEstimator(durationEstimator: durationEstimator).forecast(
               for: workout, athlete: athlete, history: history, before: cutoff, excluding: excludedActivityID
           ) {
            return (historical.steps, historical.matchedActivityCount)
        }
        return (paceModelStepProjections(workout: workout, athlete: athlete), 0)
    }

    /// The steps projected at ``AthleteProfile/paceModel``'s paces.
    private func paceModelStepProjections(workout: StructuredWorkout, athlete: AthleteProfile) -> [StepProjection] {
        let zoneModel = athlete.currentHeartRateZoneSettings.map { HeartRateZoneModel(settings: $0) }
        var projections: [StepProjection] = []
        for (blockIndex, block) in workout.blocks.enumerated() where block.repetitions > 0 {
            for repetition in 1...block.repetitions {
                for step in block.steps {
                    let duration = durationEstimator.duration(for: step, athlete: athlete)
                    let zone = zoneModel?.intensityZone(for: step.target)
                    let distance: Double?
                    switch step.goal {
                    case .distance(let meters):
                        distance = meters
                    case .time, .open:
                        distance = zone.map { duration / athlete.paceModel.secondsPerMeter(atZone: max($0, 1)) }
                    }
                    projections.append(StepProjection(
                        block: blockIndex, repetition: repetition, step: step,
                        duration: duration, zone: zone, distanceMeters: distance
                    ))
                }
            }
        }
        return projections
    }

    /// Projects `workout` using the athlete's current heart-rate zone settings — planning is
    /// always about who the athlete is now, matching ``TRIMPPlanEstimator``.
    ///
    /// - Parameters: As ``stepProjections(workout:athlete:history:before:excluding:)``.
    func project(
        workout: StructuredWorkout, athlete: AthleteProfile, history: PaceHistory = .empty,
        before cutoff: Date = .distantFuture, excluding excludedActivityID: UUID? = nil
    ) -> Projection {
        guard athlete.currentHeartRateZoneSettings != nil else {
            return Projection(distanceMeters: nil, duration: durationEstimator.duration(for: workout, athlete: athlete), timeInZone: TimeInZone())
        }
        var totalDuration: TimeInterval = 0
        var totalDistance: Double = 0
        var seconds: [Int: TimeInterval] = [:]
        let stepForecast = forecast(workout: workout, athlete: athlete, history: history, before: cutoff, excluding: excludedActivityID)
        for projection in stepForecast.steps {
            totalDuration += projection.duration
            totalDistance += projection.distanceMeters ?? 0
            seconds[projection.zone ?? 3, default: 0] += projection.duration
        }
        return Projection(
            distanceMeters: totalDistance, duration: totalDuration, timeInZone: TimeInZone(seconds: seconds),
            matchedActivityCount: stepForecast.matchedActivityCount
        )
    }
}
