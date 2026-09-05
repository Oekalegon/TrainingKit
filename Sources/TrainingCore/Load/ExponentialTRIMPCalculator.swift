import Foundation

/// Computes training load using Banister's exponential heart-rate TRIMP.
///
/// Integrates trapezoidally between consecutive heart-rate samples: for each pair, the average
/// heart-rate-reserve ratio is weighted by `a * exp(b * ratio)` and multiplied by the elapsed
/// time in minutes. Gaps longer than ``gapThresholdSeconds`` between samples are treated as a
/// pause and are not integrated, rather than being bridged across the gap.
public struct ExponentialTRIMPCalculator: LoadCalculator {
    /// The `(a, b)` weighting coefficients, selected per ``AthleteProfile/sex``.
    public var coefficients: TRIMPCoefficients
    /// Gaps between consecutive samples longer than this are treated as a pause and skipped.
    public var gapThresholdSeconds: TimeInterval

    /// Creates an exponential TRIMP calculator.
    ///
    /// - Parameters:
    ///   - coefficients: The `(a, b)` weighting coefficients; defaults to Banister's originals.
    ///   - gapThresholdSeconds: Gaps longer than this are treated as a pause; defaults to 60.
    public init(coefficients: TRIMPCoefficients = TRIMPCoefficients(), gapThresholdSeconds: TimeInterval = 60) {
        self.coefficients = coefficients
        self.gapThresholdSeconds = gapThresholdSeconds
    }

    /// Integrates trapezoidal TRIMP over `activity.heartRate`, using the heart-rate zone
    /// settings effective on `activity.start`.
    ///
    /// - Parameters:
    ///   - activity: The activity to score; must have at least one heart-rate sample.
    ///   - athlete: Supplies ``AthleteProfile/sex`` (for coefficient selection) and the
    ///     heart-rate zone settings effective on the activity's date.
    /// - Returns: A ``TrainingLoad`` with `method: .exponentialTRIMP` and full confidence.
    /// - Throws: ``LoadError/noHeartRateData`` if `activity.heartRate` is empty,
    ///   ``LoadError/invalidHeartRateData(reason:)`` if any sample is NaN or negative, or
    ///   ``LoadError/missingHeartRateZoneSettings`` if the athlete has no settings on record.
    public func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad {
        guard !activity.heartRate.isEmpty else {
            throw LoadError.noHeartRateData
        }

        for sample in activity.heartRate {
            guard sample.bpm.isFinite, sample.bpm >= 0 else {
                throw LoadError.invalidHeartRateData(reason: "bpm must be a non-negative, finite number")
            }
        }

        guard let settings = athlete.heartRateZoneSettings(asOf: activity.start) else {
            throw LoadError.missingHeartRateZoneSettings
        }

        let samples = activity.heartRate.sorted { $0.time < $1.time }
        let zoneModel = HeartRateZoneModel(settings: settings)
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
