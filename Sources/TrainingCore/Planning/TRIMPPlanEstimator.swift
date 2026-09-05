import Foundation

/// The MVP 1 ``PlannedLoadEstimator``: walks a workout's steps and applies the same Banister
/// TRIMP formula used by ``ExponentialTRIMPCalculator``, using each step's target intensity in
/// place of measured heart rate.
///
/// `.pace` and `.power` targets are approximated at a default mid-high zone ratio, since MVP 1's
/// zone model is heart-rate only; refining this is a natural follow-up once pace/power zone
/// models exist.
public struct TRIMPPlanEstimator: PlannedLoadEstimator {
    public var coefficients: TRIMPCoefficients
    public var durationEstimator: WorkoutDurationEstimator
    /// Estimate confidence relative to a measured load, used to mark this as `.estimatedFromPlan`.
    public var confidence: Double

    public init(
        coefficients: TRIMPCoefficients = TRIMPCoefficients(),
        durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator(),
        confidence: Double = 0.7
    ) {
        self.coefficients = coefficients
        self.durationEstimator = durationEstimator
        self.confidence = confidence
    }

    public func estimatedLoad(for workout: StructuredWorkout, athlete: AthleteProfile) -> TrainingLoad {
        // Planning is always about who the athlete is now, not who they were on some past date,
        // so this uses the current settings rather than an as-of-date lookup. If none have been
        // recorded yet, there's no ratio to compute against; return a zero-confidence zero rather
        // than making the protocol throwing for what should be a transient onboarding state.
        guard let settings = athlete.currentHeartRateZoneSettings else {
            Logging.load.warning("estimatedLoad(for:athlete:) called with no heartRateZoneHistory recorded; returning a zero-confidence 0 rather than a real estimate for workout \(workout.id, privacy: .public)")
            return TrainingLoad(value: 0, method: .estimatedFromPlan, confidence: 0)
        }
        let zoneModel = HeartRateZoneModel(settings: settings)
        let (a, b) = coefficients.coefficients(for: athlete.sex)

        var total = 0.0
        for block in workout.blocks {
            var blockTotal = 0.0
            for step in block.steps {
                let duration = durationEstimator.duration(for: step, athlete: athlete)
                let ratio = ratio(for: step.target, zoneModel: zoneModel)
                let weight = a * exp(b * ratio)
                blockTotal += (duration / 60) * ratio * weight
            }
            total += blockTotal * Double(block.repetitions)
        }

        return TrainingLoad(value: total, method: .estimatedFromPlan, confidence: confidence)
    }

    private func ratio(for target: IntensityTarget?, zoneModel: HeartRateZoneModel) -> Double {
        guard let target else {
            return zoneModel.zoneMidpointRatio(3) ?? 0.75
        }
        switch target {
        case .heartRateZone(let zone):
            return zoneModel.zoneMidpointRatio(zone) ?? zoneModel.zoneMidpointRatio(3) ?? 0.75
        case .heartRateRange(let low, let high):
            return (zoneModel.deltaHRRatio(for: low) + zoneModel.deltaHRRatio(for: high)) / 2
        case .pace, .power:
            // Approximation: MVP 1 has no pace/power zone model, so assume a threshold-adjacent effort.
            return zoneModel.zoneMidpointRatio(4) ?? 0.85
        case .rpe(let rpe):
            return Double(rpe) / 10
        }
    }
}
