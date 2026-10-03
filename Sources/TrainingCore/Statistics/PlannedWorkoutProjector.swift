import Foundation

/// Projects the distance/duration/time-in-zone a planned workout would produce, for weekly/period
/// statistics on a day that isn't done yet.
///
/// Walks each step the same way ``TRIMPPlanEstimator`` walks it for load: `.distance` steps
/// contribute their meters directly, `.time`/`.open` steps convert to distance via
/// ``AthleteProfile/paceModel`` at the step's target zone, using
/// ``HeartRateZoneModel/intensityRatio(for:)`` so the assumed intensity always matches the one
/// `TRIMPPlanEstimator` used to estimate the same workout's load.
struct PlannedWorkoutProjector: Sendable {
    /// Turns a workout step's `StepGoal` into a duration.
    var durationEstimator: WorkoutDurationEstimator

    /// The projected distance/duration/time-in-zone for one workout.
    struct Projection: Sendable {
        let distanceMeters: Double?
        let duration: TimeInterval
        let timeInZone: TimeInZone
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
    /// duration, zone and distance. ``project(workout:athlete:)`` sums these.
    func stepProjections(workout: StructuredWorkout, athlete: AthleteProfile) -> [StepProjection] {
        let zoneModel = athlete.currentHeartRateZoneSettings.map { HeartRateZoneModel(settings: $0) }
        let boundaries = zoneModel.flatMap { TimeInZoneBuilder.zoneBoundaries($0) }
        var projections: [StepProjection] = []
        for (blockIndex, block) in workout.blocks.enumerated() where block.repetitions > 0 {
            for repetition in 1...block.repetitions {
                for step in block.steps {
                    let duration = durationEstimator.duration(for: step, athlete: athlete)
                    var zone: Int?
                    if let zoneModel {
                        let ratio = zoneModel.intensityRatio(for: step.target)
                        zone = boundaries.map { TimeInZoneBuilder.zone(for: ratio, boundaries: $0) } ?? 3
                    }
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
    func project(workout: StructuredWorkout, athlete: AthleteProfile) -> Projection {
        guard athlete.currentHeartRateZoneSettings != nil else {
            return Projection(distanceMeters: nil, duration: durationEstimator.duration(for: workout, athlete: athlete), timeInZone: TimeInZone())
        }
        var totalDuration: TimeInterval = 0
        var totalDistance: Double = 0
        var seconds: [Int: TimeInterval] = [:]
        for projection in stepProjections(workout: workout, athlete: athlete) {
            totalDuration += projection.duration
            totalDistance += projection.distanceMeters ?? 0
            seconds[projection.zone ?? 3, default: 0] += projection.duration
        }
        return Projection(distanceMeters: totalDistance, duration: totalDuration, timeInZone: TimeInZone(seconds: seconds))
    }
}
