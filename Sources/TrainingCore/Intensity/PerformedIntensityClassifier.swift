import Foundation

/// Classifies a completed ``Activity``'s intensity from its recorded heart rate.
///
/// Heart rate is a lagged, noisy view of effort, so it is cleaned before it is compared to the
/// zones:
///
/// 1. It is resampled onto a regular grid within each uninterrupted stretch of samples (gaps
///    longer than ``gapThresholdSeconds`` are pauses and are excluded, as for time in zone).
/// 2. It is lightly smoothed to suppress sensor jitter.
/// 3. The lag is undone by treating heart rate as a first-order response to effort:
///    `effort = heartRate + lag × d(heartRate)/dt`. A rise is credited to the interval that caused
///    it instead of the recovery after, and a slow fall is not mistaken for continued effort.
/// 4. Only stretches that last at least ``IntensityClassifierParameters/minimumExcursionSeconds``
///    count as hard (zones 4–5) or moderate (zone 3), so brief drifts and spikes are ignored.
///
/// The result goes through the same ladder as ``PlannedIntensityClassifier``, so a planned and a
/// performed session are directly comparable.
public struct PerformedIntensityClassifier: Sendable {
    /// The thresholds applied to the session's time in zones.
    public var parameters: IntensityClassifierParameters
    /// Gaps between consecutive heart-rate samples longer than this are treated as a pause.
    public var gapThresholdSeconds: TimeInterval

    /// The spacing of the resampled heart-rate grid, in seconds.
    private static let gridSeconds: TimeInterval = 5
    /// How many grid points the smoothing moving average spans (centred).
    private static let smoothingPoints = 3

    /// Creates a classifier.
    ///
    /// - Parameters:
    ///   - parameters: The thresholds applied to the session's time in zones.
    ///   - gapThresholdSeconds: Gaps longer than this are excluded; defaults to the 60 seconds
    ///     ``StatisticsCalculator`` uses, so time in zone and intensity agree on what counts.
    public init(
        parameters: IntensityClassifierParameters = IntensityClassifierParameters(),
        gapThresholdSeconds: TimeInterval = 60
    ) {
        self.parameters = parameters
        self.gapThresholdSeconds = gapThresholdSeconds
    }

    /// Classifies `activity` for `athlete`, or returns `nil` when there is nothing to go on.
    ///
    /// Uses the athlete's zone settings effective on `activity.start`. Without heart-rate data
    /// (or without recorded zone settings) it falls back to the activity's
    /// ``Activity/perceivedExertion`` (Borg CR10) with ``IntensityAssessment/Confidence/low``
    /// confidence, and returns `nil` if that is missing too. Confidence is at best
    /// ``IntensityAssessment/Confidence/medium`` for heart rate alone, and ``IntensityAssessment/Confidence/low``
    /// when the samples cover less than half of the activity.
    public func assess(_ activity: Activity, athlete: AthleteProfile) -> IntensityAssessment? {
        guard let settings = athlete.heartRateZoneSettings(asOf: activity.start),
              let boundaries = TimeInZoneBuilder.zoneBoundaries(HeartRateZoneModel(settings: settings))
        else {
            return exertionAssessment(for: activity)
        }
        let zoneModel = HeartRateZoneModel(settings: settings)

        var totalSeconds: TimeInterval = 0
        var hardSeconds: TimeInterval = 0
        var moderateSeconds: TimeInterval = 0
        var aboveFirstZoneSeconds: TimeInterval = 0

        for run in uninterruptedRuns(of: activity.heartRate) {
            let effort = effortSeries(for: run, settings: settings)
            let zones = effort.map { TimeInZoneBuilder.zone(for: zoneModel.deltaHRRatio(for: $0), boundaries: boundaries) }

            let hard = sustained(zones, where: { $0 >= 4 })
            let tempoOrAbove = sustained(zones, where: { $0 >= 3 })
            let aerobicOrAbove = sustained(zones, where: { $0 >= 2 })

            totalSeconds += Double(zones.count) * Self.gridSeconds
            for index in zones.indices {
                if hard[index] {
                    hardSeconds += Self.gridSeconds
                } else if tempoOrAbove[index] {
                    moderateSeconds += Self.gridSeconds
                }
                if aerobicOrAbove[index] {
                    aboveFirstZoneSeconds += Self.gridSeconds
                }
            }
        }

        guard totalSeconds > 0 else { return exertionAssessment(for: activity) }

        let category = parameters.category(
            totalSeconds: totalSeconds,
            hardSeconds: hardSeconds,
            moderateSeconds: moderateSeconds,
            aboveFirstZoneSeconds: aboveFirstZoneSeconds
        )
        let coverage = totalSeconds / max(activity.duration, totalSeconds)
        return IntensityAssessment(
            category: category,
            source: .measured,
            confidence: coverage >= 0.5 ? .medium : .low,
            hardSeconds: hardSeconds,
            moderateSeconds: moderateSeconds
        )
    }

    // MARK: - Heart-rate cleaning

    /// Splits `samples` into stretches with no gap longer than ``gapThresholdSeconds``, dropping
    /// samples that share a timestamp and stretches too short to interpolate.
    private func uninterruptedRuns(of samples: [HeartRateSample]) -> [[HeartRateSample]] {
        let sorted = samples.sorted { $0.time < $1.time }
        var runs: [[HeartRateSample]] = []
        var current: [HeartRateSample] = []
        for sample in sorted {
            guard let last = current.last else {
                current = [sample]
                continue
            }
            let dt = sample.time.timeIntervalSince(last.time)
            if dt <= 0 { continue }
            if dt > gapThresholdSeconds {
                if current.count >= 2 { runs.append(current) }
                current = [sample]
            } else {
                current.append(sample)
            }
        }
        if current.count >= 2 { runs.append(current) }
        return runs
    }

    /// The lag-corrected effort, in bpm, on the regular grid over `run`.
    private func effortSeries(for run: [HeartRateSample], settings: HeartRateZoneSettings) -> [Double] {
        let smoothed = smooth(resample(run))
        let lag = parameters.heartRateLagSeconds
        guard lag > 0, smoothed.count > 1 else { return smoothed }

        let last = smoothed.count - 1
        return smoothed.indices.map { index in
            let before = max(index - 1, 0)
            let after = min(index + 1, last)
            let slope = (smoothed[after] - smoothed[before]) / (Double(after - before) * Self.gridSeconds)
            let effort = smoothed[index] + lag * slope
            return min(max(effort, settings.restingHeartRateBPM), settings.maxHeartRateBPM)
        }
    }

    /// Linearly interpolated bpm every ``gridSeconds`` from the run's first to last sample.
    private func resample(_ run: [HeartRateSample]) -> [Double] {
        guard let first = run.first, let last = run.last else { return [] }
        let duration = last.time.timeIntervalSince(first.time)
        let count = Int(duration / Self.gridSeconds) + 1
        var result: [Double] = []
        result.reserveCapacity(count)

        var segment = 0
        for step in 0..<count {
            let time = first.time.addingTimeInterval(Double(step) * Self.gridSeconds)
            while segment < run.count - 2, run[segment + 1].time < time {
                segment += 1
            }
            let start = run[segment]
            let end = run[segment + 1]
            let span = end.time.timeIntervalSince(start.time)
            let fraction = min(max(time.timeIntervalSince(start.time) / span, 0), 1)
            result.append(start.bpm + (end.bpm - start.bpm) * fraction)
        }
        return result
    }

    /// A centred moving average, narrowed at the ends.
    private func smooth(_ values: [Double]) -> [Double] {
        let half = Self.smoothingPoints / 2
        return values.indices.map { index in
            let lower = max(index - half, 0)
            let upper = min(index + half, values.count - 1)
            let window = values[lower...upper]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// Marks the points that belong to a stretch of consecutive points satisfying `predicate`
    /// lasting at least ``IntensityClassifierParameters/minimumExcursionSeconds``.
    private func sustained(_ zones: [Int], where predicate: (Int) -> Bool) -> [Bool] {
        var marks = [Bool](repeating: false, count: zones.count)
        var start = 0
        while start < zones.count {
            guard predicate(zones[start]) else {
                start += 1
                continue
            }
            var end = start
            while end < zones.count, predicate(zones[end]) { end += 1 }
            if Double(end - start) * Self.gridSeconds >= parameters.minimumExcursionSeconds {
                for index in start..<end { marks[index] = true }
            }
            start = end
        }
        return marks
    }

    // MARK: - Perceived exertion fallback

    /// The session's category from a whole-session Borg CR10 rating, for activities without usable
    /// heart rate: 1–2 very low, 3–4 low, 5–6 medium, 7 and up high.
    private func exertionAssessment(for activity: Activity) -> IntensityAssessment? {
        guard let exertion = activity.perceivedExertion else { return nil }
        let category: IntensityCategory
        switch exertion {
        case ...2: category = .veryLow
        case 3...4: category = .low
        case 5...6: category = .medium
        default: category = .high
        }
        return IntensityAssessment(category: category, source: .measured, confidence: .low, hardSeconds: 0, moderateSeconds: 0)
    }
}
