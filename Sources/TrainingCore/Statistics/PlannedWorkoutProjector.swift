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
        /// `nil` when a time-based step can't be converted (no heart-rate zone settings).
        let distanceMeters: Double?
    }

    /// Every step of `workout` with its block repetitions expanded, each with its projected
    /// duration and distance, converted the same way ``project(workout:athlete:)`` does.
    func stepProjections(workout: StructuredWorkout, athlete: AthleteProfile) -> [StepProjection] {
        let zoneModel = athlete.currentHeartRateZoneSettings.map { HeartRateZoneModel(settings: $0) }
        let boundaries = zoneModel.flatMap { TimeInZoneBuilder.zoneBoundaries($0) }
        var projections: [StepProjection] = []
        for (blockIndex, block) in workout.blocks.enumerated() {
            for repetition in 1...max(block.repetitions, 1) where block.repetitions > 0 {
                for step in block.steps {
                    let duration = durationEstimator.duration(for: step, athlete: athlete)
                    let distance: Double?
                    switch step.goal {
                    case .distance(let meters):
                        distance = meters
                    case .time, .open:
                        if let zoneModel {
                            let ratio = zoneModel.intensityRatio(for: step.target)
                            let zone = boundaries.map { TimeInZoneBuilder.zone(for: ratio, boundaries: $0) } ?? 3
                            distance = duration / athlete.paceModel.secondsPerMeter(atZone: max(zone, 1))
                        } else {
                            distance = nil
                        }
                    }
                    projections.append(StepProjection(
                        block: blockIndex, repetition: repetition, step: step, duration: duration, distanceMeters: distance
                    ))
                }
            }
        }
        return projections
    }

    /// Projects `workout` using the athlete's current heart-rate zone settings — planning is
    /// always about who the athlete is now, matching ``TRIMPPlanEstimator``.
    func project(workout: StructuredWorkout, athlete: AthleteProfile) -> Projection {
        guard let settings = athlete.currentHeartRateZoneSettings else {
            return Projection(distanceMeters: nil, duration: durationEstimator.duration(for: workout, athlete: athlete), timeInZone: TimeInZone())
        }
        let zoneModel = HeartRateZoneModel(settings: settings)
        let boundaries = TimeInZoneBuilder.zoneBoundaries(zoneModel)

        var totalDuration: TimeInterval = 0
        var totalDistance: Double = 0
        var seconds: [Int: TimeInterval] = [:]

        for block in workout.blocks {
            for _ in 0..<block.repetitions {
                for step in block.steps {
                    let duration = durationEstimator.duration(for: step, athlete: athlete)
                    let ratio = zoneModel.intensityRatio(for: step.target)
                    let zone = boundaries.map { TimeInZoneBuilder.zone(for: ratio, boundaries: $0) } ?? 3

                    totalDuration += duration
                    seconds[zone, default: 0] += duration

                    switch step.goal {
                    case .distance(let meters):
                        totalDistance += meters
                    case .time, .open:
                        totalDistance += duration / athlete.paceModel.secondsPerMeter(atZone: max(zone, 1))
                    }
                }
            }
        }

        return Projection(distanceMeters: totalDistance, duration: totalDuration, timeInZone: TimeInZone(seconds: seconds))
    }
}
