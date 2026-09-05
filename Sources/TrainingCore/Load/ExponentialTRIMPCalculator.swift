import Foundation

/// Computes training load using Banister's exponential heart-rate TRIMP.
///
/// Integrates trapezoidally between consecutive heart-rate samples: for each pair, the average
/// heart-rate-reserve ratio is weighted by `a * exp(b * ratio)` and multiplied by the elapsed
/// time in minutes. Gaps longer than ``gapThresholdSeconds`` between samples are treated as a
/// pause and are not integrated, rather than being bridged across the gap.
public struct ExponentialTRIMPCalculator: LoadCalculator {
    public var coefficients: TRIMPCoefficients
    /// Gaps between consecutive samples longer than this are treated as a pause and skipped.
    public var gapThresholdSeconds: TimeInterval

    public init(coefficients: TRIMPCoefficients = TRIMPCoefficients(), gapThresholdSeconds: TimeInterval = 60) {
        self.coefficients = coefficients
        self.gapThresholdSeconds = gapThresholdSeconds
    }

    public func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad {
        guard !activity.heartRate.isEmpty else {
            throw LoadError.noHeartRateData
        }

        for sample in activity.heartRate {
            guard sample.bpm.isFinite, sample.bpm >= 0 else {
                throw LoadError.invalidHeartRateData(reason: "bpm must be a non-negative, finite number")
            }
        }

        let samples = activity.heartRate.sorted { $0.time < $1.time }
        let zoneModel = HeartRateZoneModel(athlete: athlete)
        let (a, b) = coefficients.coefficients(for: athlete.sex)

        var totalTRIMP = 0.0
        for (previous, current) in zip(samples, samples.dropFirst()) {
            let dtSeconds = current.time.timeIntervalSince(previous.time)
            guard dtSeconds > 0, dtSeconds <= gapThresholdSeconds else { continue }

            let previousRatio = zoneModel.deltaHRRatio(for: previous.bpm)
            let currentRatio = zoneModel.deltaHRRatio(for: current.bpm)
            let averageRatio = (previousRatio + currentRatio) / 2
            let weight = a * exp(b * averageRatio)
            let dtMinutes = dtSeconds / 60
            totalTRIMP += dtMinutes * averageRatio * weight
        }

        return TrainingLoad(value: totalTRIMP, method: .exponentialTRIMP, confidence: 1.0)
    }
}
