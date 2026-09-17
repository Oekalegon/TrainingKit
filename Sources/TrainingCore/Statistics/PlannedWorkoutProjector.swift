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
