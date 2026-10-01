import Foundation

/// Finds the highest heart rate an athlete actually *held* during an activity, as evidence for
/// raising their max heart rate.
///
/// Heart-rate sensors produce three kinds of false highs, and each is handled separately:
/// - **Short spikes** (chest-strap static, poor contact). The peak is the highest value the heart
///   rate stayed at or above for at least ``sustainSeconds``: for each sample, take the minimum
///   over the window that starts there and spans `sustainSeconds`, then the largest of those
///   minimums. A lone spike only ever raises a window's maximum, never its minimum.
/// - **Cadence lock**. An optical wrist sensor can lock onto running cadence and report it as heart
///   rate, often for minutes. It shows up as a jump no real heart makes: a rise faster than
///   ``maximumRiseBPMPerSecond``, measured against the sample at least ``riseWindowSeconds``
///   earlier. Rates are measured on a 3-sample running median, which keeps a lock's sharp edge
///   but removes single spikes and most sensor noise, so neither is mistaken for a lock. Samples
///   from such a jump up until the matching fast drop are discarded. A jump with no matching drop
///   before the recording ends is kept: it can't be told apart from a genuinely steep rise, and
///   discarding everything after a misfire would throw away the workout's real peak. Such a lock
///   can therefore still reach the athlete, whose confirmation is the backstop.
/// - **Stuck readings**. A held value above ``plausibleMaximumBPM`` is skipped as a sensor fault,
///   and the best plausible value elsewhere in the activity is still found.
///
/// Gaps longer than ``maximumGapSeconds`` (a paused workout, a sensor dropout) split the samples
/// into separate runs, and a window never spans a gap or a discarded stretch. Non-finite or
/// non-positive samples are dropped.
///
/// None of this is proof: the result is only ever offered to the athlete to confirm.
public struct PeakHeartRateDetector: Sendable {
    /// A heart rate held for at least ``PeakHeartRateDetector/sustainSeconds``.
    public struct Peak: Sendable, Hashable {
        /// The held heart rate, in beats per minute.
        public let bpm: Double
        /// When the window that held it began.
        public let time: Date
    }

    /// The shortest interval a rise is measured over, in seconds. Shorter intervals would turn
    /// ordinary sample-to-sample noise at 1 s sampling into apparent jumps.
    public static let riseWindowSeconds: TimeInterval = 5

    /// How long the heart rate must stay at or above a value for that value to count, in seconds.
    public let sustainSeconds: TimeInterval
    /// The longest gap between consecutive samples still treated as continuous, in seconds.
    public let maximumGapSeconds: TimeInterval
    /// The highest held value accepted as physiological, in beats per minute. Windows holding more
    /// are treated as a sensor fault and skipped.
    public let plausibleMaximumBPM: Double
    /// The fastest rise (or fall) a real heart rate makes, in beats per minute per second. A faster
    /// jump marks the start (or end) of a cadence lock.
    public let maximumRiseBPMPerSecond: Double

    /// Creates a peak detector.
    ///
    /// Out-of-range arguments are clamped to usable values: a sustain window and a gap tolerance of
    /// at least 1 s each, a plausible maximum of at least 100 bpm, and a maximum rise of at least
    /// 1 bpm/s. Non-finite arguments fall back to the defaults.
    ///
    /// - Parameters:
    ///   - sustainSeconds: How long a value must be held; defaults to 10 s, which is two or three
    ///     samples at Apple Watch's usual workout sampling interval.
    ///   - maximumGapSeconds: The longest sample gap still treated as continuous; defaults to 15 s.
    ///   - plausibleMaximumBPM: The highest held value accepted; defaults to 230 bpm.
    ///   - maximumRiseBPMPerSecond: The fastest physiological rise or fall; defaults to 5 bpm/s
    ///     (25 bpm in 5 s). Heart rate at the start of a hard interval rises at about 1–3 bpm/s,
    ///     while a cadence lock typically jumps 30 bpm or more between two samples.
    public init(
        sustainSeconds: TimeInterval = 10,
        maximumGapSeconds: TimeInterval = 15,
        plausibleMaximumBPM: Double = 230,
        maximumRiseBPMPerSecond: Double = 5
    ) {
        self.sustainSeconds = sustainSeconds.isFinite ? max(sustainSeconds, 1) : 10
        self.maximumGapSeconds = maximumGapSeconds.isFinite ? max(maximumGapSeconds, 1) : 15
        self.plausibleMaximumBPM = plausibleMaximumBPM.isFinite ? max(plausibleMaximumBPM, 100) : 230
        self.maximumRiseBPMPerSecond = maximumRiseBPMPerSecond.isFinite ? max(maximumRiseBPMPerSecond, 1) : 5
    }

    /// The highest plausible heart rate held for at least ``sustainSeconds`` in `samples`.
    ///
    /// - Parameter samples: Heart-rate samples in any order.
    /// - Returns: The highest held value and when its window began, or `nil` when no stretch of
    ///   trustworthy samples spans ``sustainSeconds`` with a plausible value.
    public func sustainedPeak(in samples: [HeartRateSample]) -> Peak? {
        let valid = samples
            .filter { $0.bpm.isFinite && $0.bpm > 0 }
            .sorted { $0.time < $1.time }
        var best: Peak?
        for run in runs(of: valid) {
            for stretch in withoutLockedStretches(run) {
                guard let peak = sustainedPeak(inStretch: stretch) else { continue }
                if peak.bpm > (best?.bpm ?? -.infinity) {
                    best = peak
                }
            }
        }
        return best
    }

    /// Splits time-sorted samples wherever consecutive samples are more than
    /// ``maximumGapSeconds`` apart.
    private func runs(of samples: [HeartRateSample]) -> [[HeartRateSample]] {
        var result: [[HeartRateSample]] = []
        var current: [HeartRateSample] = []
        for sample in samples {
            if let last = current.last, sample.time.timeIntervalSince(last.time) > maximumGapSeconds {
                result.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// `run` with suspected cadence-lock stretches removed, as the continuous stretches left over.
    ///
    /// Each sample's rate of change is measured, on the 3-sample running median, against the latest
    /// sample at least ``riseWindowSeconds`` earlier. A rise faster than ``maximumRiseBPMPerSecond``
    /// starts a suspected lock, and a fall that fast confirms and ends it: the locked samples are
    /// dropped and the falling sample starts a new stretch. A suspected lock that never sees that
    /// fall is kept, joined to the stretch before it. The samples kept are the original ones, not
    /// the median.
    private func withoutLockedStretches(_ run: [HeartRateSample]) -> [[HeartRateSample]] {
        let smoothed = Self.runningMedian(of: run.map(\.bpm))
        var stretches: [[HeartRateSample]] = []
        var current: [HeartRateSample] = []
        var suspected: [HeartRateSample] = []
        var locked = false
        var reference = run.startIndex
        for index in run.indices {
            while reference + 1 < index,
                run[index].time.timeIntervalSince(run[reference + 1].time) >= Self.riseWindowSeconds {
                reference += 1
            }
            let elapsed = run[index].time.timeIntervalSince(run[reference].time)
            let rate = elapsed >= Self.riseWindowSeconds ? (smoothed[index] - smoothed[reference]) / elapsed : 0
            if !locked, rate > maximumRiseBPMPerSecond {
                locked = true
            } else if locked, rate < -maximumRiseBPMPerSecond {
                // Both edges seen: a lock. Drop it; the stretch before it stands on its own.
                locked = false
                suspected = []
                if !current.isEmpty { stretches.append(current) }
                current = []
            }
            if locked {
                suspected.append(run[index])
            } else {
                current.append(run[index])
            }
        }
        current += suspected
        if !current.isEmpty { stretches.append(current) }
        return stretches
    }

    /// Each value's median with its neighbours (the mean of the two at either end), which removes a
    /// single-sample spike entirely while leaving a step change sharp.
    private static func runningMedian(of values: [Double]) -> [Double] {
        values.indices.map { index in
            let neighbourhood = values[max(index - 1, 0)...min(index + 1, values.count - 1)].sorted()
            return neighbourhood.count == 3 ? neighbourhood[1] : neighbourhood.reduce(0, +) / Double(neighbourhood.count)
        }
    }

    /// The best plausible held value within one continuous stretch: for each starting sample, the
    /// minimum over samples up to and including the first one at least ``sustainSeconds`` later.
    /// Windows holding more than ``plausibleMaximumBPM`` are skipped.
    private func sustainedPeak(inStretch stretch: [HeartRateSample]) -> Peak? {
        var best: Peak?
        var windowEnd = stretch.startIndex
        for start in stretch.indices {
            if windowEnd < start { windowEnd = start }
            while windowEnd < stretch.endIndex,
                stretch[windowEnd].time.timeIntervalSince(stretch[start].time) < sustainSeconds {
                windowEnd += 1
            }
            // No sample at least `sustainSeconds` after `start`: this and every later start in the
            // stretch fall short of a full window.
            guard windowEnd < stretch.endIndex else { break }
            let held = stretch[start...windowEnd].lazy.map(\.bpm).min() ?? 0
            if held <= plausibleMaximumBPM, held > (best?.bpm ?? -.infinity) {
                best = Peak(bpm: held, time: stretch[start].time)
            }
        }
        return best
    }
}
