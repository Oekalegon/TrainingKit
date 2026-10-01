import Foundation

/// Finds the highest heart rate an athlete actually *held* during an activity, as evidence for
/// raising their max heart rate.
///
/// A single sample is not trustworthy enough to change max heart rate on. Optical wrist sensors
/// briefly lock onto running cadence, and chest straps spike on static or poor contact; either can
/// produce one reading well above anything the heart did. So the peak is the highest value the
/// heart rate stayed at or above for at least ``sustainSeconds``: for each sample, take the
/// minimum over the window that starts there and spans `sustainSeconds`, then take the largest of
/// those minimums. A lone spike only ever raises the window's maximum, never its minimum, so it is
/// ignored.
///
/// Gaps longer than ``maximumGapSeconds`` (a paused workout, a sensor dropout) break the samples
/// into separate runs, and a window never spans a gap. Non-finite or non-positive samples are
/// dropped, and a held value above ``plausibleMaximumBPM`` is rejected as a sensor fault rather
/// than reported.
public struct PeakHeartRateDetector: Sendable {
    /// A heart rate held for at least ``PeakHeartRateDetector/sustainSeconds``.
    public struct Peak: Sendable, Hashable {
        /// The held heart rate, in beats per minute.
        public let bpm: Double
        /// When the window that held it began.
        public let time: Date
    }

    /// How long the heart rate must stay at or above a value for that value to count, in seconds.
    public let sustainSeconds: TimeInterval
    /// The longest gap between consecutive samples still treated as continuous, in seconds.
    public let maximumGapSeconds: TimeInterval
    /// The highest held value accepted as physiological, in beats per minute. Anything above it is
    /// treated as a sensor fault.
    public let plausibleMaximumBPM: Double

    /// Creates a peak detector.
    ///
    /// Out-of-range arguments are clamped to usable values: a sustain window and a gap tolerance of
    /// at least 1 s each, and a plausible maximum of at least 100 bpm. Non-finite arguments fall
    /// back to the defaults.
    ///
    /// - Parameters:
    ///   - sustainSeconds: How long a value must be held; defaults to 10 s, which is two or three
    ///     samples at Apple Watch's usual workout sampling interval.
    ///   - maximumGapSeconds: The longest sample gap still treated as continuous; defaults to 15 s.
    ///   - plausibleMaximumBPM: The highest held value accepted; defaults to 230 bpm.
    public init(sustainSeconds: TimeInterval = 10, maximumGapSeconds: TimeInterval = 15, plausibleMaximumBPM: Double = 230) {
        self.sustainSeconds = sustainSeconds.isFinite ? max(sustainSeconds, 1) : 10
        self.maximumGapSeconds = maximumGapSeconds.isFinite ? max(maximumGapSeconds, 1) : 15
        self.plausibleMaximumBPM = plausibleMaximumBPM.isFinite ? max(plausibleMaximumBPM, 100) : 230
    }

    /// The highest heart rate held for at least ``sustainSeconds`` in `samples`.
    ///
    /// - Parameter samples: Heart-rate samples in any order.
    /// - Returns: The highest held value and when its window began, or `nil` when no run of samples
    ///   spans ``sustainSeconds`` or the highest held value is implausible.
    public func sustainedPeak(in samples: [HeartRateSample]) -> Peak? {
        let valid = samples
            .filter { $0.bpm.isFinite && $0.bpm > 0 }
            .sorted { $0.time < $1.time }
        var best: Peak?
        for run in runs(of: valid) {
            guard let peak = sustainedPeak(inRun: run) else { continue }
            if peak.bpm > (best?.bpm ?? -.infinity) {
                best = peak
            }
        }
        guard let best, best.bpm <= plausibleMaximumBPM else { return nil }
        return best
    }

    /// Splits time-sorted samples wherever consecutive samples are more than
    /// ``maximumGapSeconds`` apart.
    private func runs(of samples: [HeartRateSample]) -> [ArraySlice<HeartRateSample>] {
        var result: [ArraySlice<HeartRateSample>] = []
        var runStart = samples.startIndex
        for index in samples.indices.dropFirst()
        where samples[index].time.timeIntervalSince(samples[index - 1].time) > maximumGapSeconds {
            result.append(samples[runStart..<index])
            runStart = index
        }
        if runStart < samples.endIndex {
            result.append(samples[runStart...])
        }
        return result
    }

    /// The best held value within one continuous run: for each starting sample, the minimum over
    /// samples up to and including the first one at least ``sustainSeconds`` later.
    private func sustainedPeak(inRun run: ArraySlice<HeartRateSample>) -> Peak? {
        var best: Peak?
        var windowEnd = run.startIndex
        for start in run.indices {
            if windowEnd < start { windowEnd = start }
            while windowEnd < run.endIndex,
                run[windowEnd].time.timeIntervalSince(run[start].time) < sustainSeconds {
                windowEnd += 1
            }
            // No sample at least `sustainSeconds` after `start`: this and every later start in the
            // run fall short of a full window.
            guard windowEnd < run.endIndex else { break }
            let held = run[start...windowEnd].lazy.map(\.bpm).min() ?? 0
            if held > (best?.bpm ?? -.infinity) {
                best = Peak(bpm: held, time: run[start].time)
            }
        }
        return best
    }
}
