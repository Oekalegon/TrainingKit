import Foundation

/// Measures a field test's result from the activity linked to its plan (MVP2-154).
///
/// - A ``WorkoutPurpose/maxHRTest`` gives the highest heart rate held for a few seconds anywhere in
///   the activity, found by ``PeakHeartRateDetector`` (which discards short spikes and cadence lock).
/// - A ``WorkoutPurpose/lthrTest`` gives the average heart rate over the last 20 minutes of its
///   effort, Friel's protocol: the first 10 minutes of the 30 aren't used, since the heart rate is
///   still rising.
///
/// The effort is the workout's longest timed step. Its window comes from the steps the Watch recorded
/// (``Activity/steps``, laid over the plan by ``ActivityStepAligner``) when the test was started
/// from the scheduled workout; otherwise from the plan's own timing, if the activity's length is within
/// 5% of the plan's total and the end of the window isn't a cooldown (``FieldTestResult/isEstimatedFromPlan``).
/// The tolerances here (90% of the effort, 80% coverage, 5%) are our own, chosen so a result is
/// refused rather than misleading. Heart rate is averaged over time, not per sample, so uneven sampling doesn't weight the average, and gaps and implausible
/// values count as uncovered.
public struct FieldTestMeasurer: Sendable {
    /// How much of the end of the effort the lactate threshold average covers, in seconds.
    public static let lactateThresholdWindowSeconds: TimeInterval = 20 * 60
    /// The least a recorded effort may fall short of the planned one, as a fraction of it.
    static let minimumEffortFraction = 0.9
    /// The least of the averaging window that must have heart rate, as a fraction of it.
    static let minimumCoverage = 0.8
    /// How far the activity's length may differ from the plan's total when the effort is located by
    /// the plan's timing, as a fraction of the total. A recording that starts or ends this much off
    /// moves the effort's window by about as much, so it is kept tight (2.5 minutes of a 50-minute test).
    static let planTimingTolerance = 0.05
    /// The end of a plan-located window that is checked for a cooldown: its last two minutes must average
    /// at least ``tailFloorFraction`` of the whole window.
    static let tailSeconds: TimeInterval = 120
    /// See ``tailSeconds``.
    static let tailFloorFraction = 0.9

    /// Finds the held peak for a max heart rate test and the plausible ceiling for averaging.
    public let detector: PeakHeartRateDetector

    /// Creates a measurer.
    ///
    /// - Parameter detector: Finds the held peak and decides what is plausible; defaults to
    ///   ``PeakHeartRateDetector``'s defaults.
    public init(detector: PeakHeartRateDetector = PeakHeartRateDetector()) {
        self.detector = detector
    }

    /// The result of the test `workout` describes, measured from `activity`.
    ///
    /// - Parameters:
    ///   - activity: The activity linked to the test's plan.
    ///   - workout: The workout of that plan; its ``StructuredWorkout/purpose`` says what to measure.
    ///   - settings: The athlete's heart-rate settings in effect on the activity's date, for the
    ///     value on record and the resting heart rate.
    /// - Returns: The result, or `nil` when `workout` isn't a test (``WorkoutPurpose/general``).
    /// - Throws: ``FieldTestError`` when the test can't be measured.
    public func measure(
        _ activity: Activity, workout: StructuredWorkout, settings: HeartRateZoneSettings?
    ) throws(FieldTestError) -> FieldTestResult? {
        switch workout.purpose {
        case .general:
            return nil
        case .maxHRTest:
            guard let peak = detector.sustainedPeak(in: activity.heartRate) else { throw .noHeartRate }
            let value = peak.bpm.rounded()
            try checkPlausible(value, settings: settings)
            return FieldTestResult(
                measurement: .maxHeartRate, activityID: activity.id, activityStart: activity.start,
                valueBPM: value, currentBPM: settings?.maxHeartRateBPM,
                replacesMoreReliableSource: settings.map {
                    !$0.maxHeartRateSource.isReplaceable(by: .fieldTest(activityID: activity.id), asOf: activity.start)
                } ?? false
            )
        case .lthrTest:
            let effort = try effortWindow(in: activity, workout: workout)
            let windowStart = effort.window.upperBound.addingTimeInterval(-Self.lactateThresholdWindowSeconds)
            let average = try averageHeartRate(in: activity.heartRate, over: windowStart...effort.window.upperBound)
            if effort.isEstimatedFromPlan,
               !endsInEffort(activity.heartRate, window: effort.window, average: average) {
                throw .effortNotLocated
            }
            let value = average.rounded()
            try checkPlausible(value, settings: settings)
            return FieldTestResult(
                measurement: .lactateThresholdHeartRate, activityID: activity.id, activityStart: activity.start,
                valueBPM: value, currentBPM: settings?.lactateThresholdHeartRateBPM,
                isEstimatedFromPlan: effort.isEstimatedFromPlan,
                replacesMoreReliableSource: settings.flatMap { current in
                    current.lactateThresholdHeartRateBPM == nil ? nil
                        : !current.lactateThresholdSource.isReplaceable(
                            by: .fieldTest(activityID: activity.id), asOf: activity.start
                        )
                } ?? false
            )
        }
    }

    private func checkPlausible(_ value: Double, settings: HeartRateZoneSettings?) throws(FieldTestError) {
        if let resting = settings?.restingHeartRateBPM, value <= resting { throw .implausibleValue(bpm: value) }
    }

    /// When the effort ran: the recorded step if the Watch recorded one, else the plan's timing.
    private func effortWindow(
        in activity: Activity, workout: StructuredWorkout
    ) throws(FieldTestError) -> (window: ClosedRange<Date>, isEstimatedFromPlan: Bool) {
        let planned = PaceHistory.expandedSteps(of: workout)
        // The longest timed step is the effort; ties go to the earlier one.
        var effortIndex: Int?
        var effortSeconds = 0.0
        for (index, step) in planned.enumerated() {
            if case .time(let seconds) = step.step.goal, seconds > effortSeconds {
                effortIndex = index
                effortSeconds = seconds
            }
        }
        guard let effortIndex, effortSeconds >= Self.lactateThresholdWindowSeconds else { throw .effortNotLocated }

        if let aligned = ActivityStepAligner.align(activity.steps, with: workout) {
            // Steps that fit the plan but lack the effort say it wasn't done; the plan's timing mustn't
            // invent one.
            guard let recorded = aligned[effortIndex] else { throw .effortNotLocated }
            let length = recorded.end.timeIntervalSince(recorded.start)
            guard length >= effortSeconds * Self.minimumEffortFraction else { throw .effortTooShort(recordedSeconds: length) }
            return (recorded.start...recorded.end, false)
        }

        // Not started from the scheduled workout: lay the plan's own timing over the activity, which
        // only makes sense when every step is timed and the activity is about as long as the plan.
        var offset = 0.0
        var total = 0.0
        for (index, step) in planned.enumerated() {
            guard case .time(let seconds) = step.step.goal else { throw .effortNotLocated }
            if index == effortIndex { offset = total }
            total += seconds
        }
        guard abs(activity.duration - total) <= total * Self.planTimingTolerance else { throw .effortNotLocated }
        let start = activity.start.addingTimeInterval(offset)
        return (start...start.addingTimeInterval(effortSeconds), true)
    }

    /// Whether the end of `window` still looks like effort rather than a cooldown that the plan's timing
    /// wrongly placed inside it: the heart rate of its last ``tailSeconds`` is at least
    /// ``tailFloorFraction`` of the whole window's.
    private func endsInEffort(_ samples: [HeartRateSample], window: ClosedRange<Date>, average: Double) -> Bool {
        let tail = window.upperBound.addingTimeInterval(-Self.tailSeconds)...window.upperBound
        guard let tailAverage = try? averageHeartRate(in: samples, over: tail) else { return false }
        return tailAverage >= average * Self.tailFloorFraction
    }

    /// The time-weighted average of `samples` over `window`, in beats per minute.
    ///
    /// Each interval between two consecutive samples inside the window counts with the mean of their
    /// values, unless it is longer than the detector's gap tolerance or either value is not finite,
    /// not positive or above the plausible maximum; those intervals are left out, not bridged.
    private func averageHeartRate(
        in samples: [HeartRateSample], over window: ClosedRange<Date>
    ) throws(FieldTestError) -> Double {
        let inWindow = samples
            .filter { window.contains($0.time) }
            .sorted { $0.time < $1.time }
        var weighted = 0.0
        var covered = 0.0
        for (first, second) in zip(inWindow, inWindow.dropFirst()) {
            let span = second.time.timeIntervalSince(first.time)
            guard span > 0, span <= detector.maximumGapSeconds,
                  isUsable(first.bpm), isUsable(second.bpm) else { continue }
            weighted += (first.bpm + second.bpm) / 2 * span
            covered += span
        }
        let needed = window.upperBound.timeIntervalSince(window.lowerBound) * Self.minimumCoverage
        guard covered > 0, covered >= needed else { throw inWindow.isEmpty ? .noHeartRate : .insufficientHeartRate }
        return weighted / covered
    }

    private func isUsable(_ bpm: Double) -> Bool {
        bpm.isFinite && bpm > 0 && bpm <= detector.plausibleMaximumBPM
    }
}
