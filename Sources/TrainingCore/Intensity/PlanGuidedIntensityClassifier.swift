import Foundation

/// Classifies a completed ``Activity`` that was performed from a planned ``StructuredWorkout``,
/// using the plan as the statement of intent and the recorded heart rate to check it.
///
/// Heart rate alone is a poor judge of short structured work: a 1 minute rep is shorter than the
/// excursion ``PerformedIntensityClassifier`` requires, and heart rate drifts upwards on a long
/// easy run without the effort having changed. The plan resolves both — it says which parts were
/// meant to be hard — and the heart rate confirms whether they were.
///
/// **Verified plan.** When every step of the plan has a fixed duration, the steps are laid out on
/// the activity's timeline and each hard or tempo step (zone 3 and up, excluding warm-up and
/// cool-down) is checked: the 90th percentile of the lag-corrected effort during the step gives
/// the zone actually reached, and the step counts at the lower of the planned and reached zone.
/// The ladder is then applied to those verified zones. A step with too little heart-rate data
/// to check is taken at its planned zone.
///
/// **Unplanned effort.** Whole-activity heart rate (``PerformedIntensityClassifier``) can only
/// move the result one level up, never more, because heart rate can rise without a change in effort
/// (heat, drift, illness) and the plan is the better witness of what was intended. When the plan
/// can't be laid out on the timeline (distance or open steps), the planned category is instead
/// moved one level towards the measured one, in either direction.
///
/// Without usable heart rate the planned category is returned unchanged with low confidence.
///
/// The timeline assumes steps ran back to back from the activity's start.
public struct PlanGuidedIntensityClassifier: Sendable {
    /// The thresholds applied to the session's time in zones.
    public var parameters: IntensityClassifierParameters
    /// Converts step goals to durations.
    public var durationEstimator: WorkoutDurationEstimator
    /// Gaps between consecutive heart-rate samples longer than this are treated as a pause.
    public var gapThresholdSeconds: TimeInterval

    /// The percentile of a step's effort taken as the zone it reached, so a rep that only touches
    /// its target near the end, or a brief dip, doesn't decide the step.
    private static let stepEffortPercentile = 0.9
    /// The share of a step's duration that must have heart-rate data before it can be checked.
    private static let stepMinimumCoverage = 0.5
    /// The share of hard and tempo step time that must have been checked for high confidence.
    private static let verifiedShareForHighConfidence = 0.75

    /// Creates a classifier.
    public init(
        parameters: IntensityClassifierParameters = IntensityClassifierParameters(),
        durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator(),
        gapThresholdSeconds: TimeInterval = 60
    ) {
        self.parameters = parameters
        self.durationEstimator = durationEstimator
        self.gapThresholdSeconds = gapThresholdSeconds
    }

    /// Classifies `activity`, which was performed from `workout`.
    ///
    /// - Returns: An assessment with ``IntensityAssessment/Source/blended`` when heart rate was
    ///   usable, otherwise the planned assessment with low confidence.
    public func assess(_ activity: Activity, workout: StructuredWorkout, athlete: AthleteProfile) -> IntensityAssessment {
        let plannedClassifier = PlannedIntensityClassifier(parameters: parameters, durationEstimator: durationEstimator)
        let performedClassifier = PerformedIntensityClassifier(parameters: parameters, gapThresholdSeconds: gapThresholdSeconds)

        let planned = plannedClassifier.assess(workout, athlete: athlete)
        // Perceived-exertion and sparse-heart-rate results are too weak to move a planned category.
        let measured = performedClassifier.assess(activity, athlete: athlete).flatMap { $0.confidence >= .medium ? $0 : nil }

        if let verification = verify(
            activity, workout: workout, athlete: athlete,
            plannedClassifier: plannedClassifier, performedClassifier: performedClassifier
        ) {
            let verified = verification.assessment
            var category = verified.category
            var confidence = IntensityAssessment.Confidence.medium
            if let measured, measured.category > category {
                category = category.moved(toward: measured.category)
            } else if let measured, measured.category == category, verification.verifiedShare >= Self.verifiedShareForHighConfidence {
                confidence = .high
            }
            return IntensityAssessment(
                category: category,
                source: .blended,
                confidence: confidence,
                hardSeconds: verified.hardSeconds,
                moderateSeconds: verified.moderateSeconds
            )
        }

        guard let measured else {
            return IntensityAssessment(
                category: planned.category,
                source: .planned,
                confidence: .low,
                hardSeconds: planned.hardSeconds,
                moderateSeconds: planned.moderateSeconds
            )
        }

        let agrees = measured.category == planned.category
        return IntensityAssessment(
            category: planned.category.moved(toward: measured.category),
            source: .blended,
            confidence: agrees && planned.confidence >= .medium ? .high : .medium,
            hardSeconds: measured.hardSeconds,
            moderateSeconds: measured.moderateSeconds
        )
    }

    private struct Verification {
        let assessment: IntensityAssessment
        /// The share of hard and tempo step time whose heart rate could be checked; 1 if the plan
        /// has no such steps.
        let verifiedShare: Double
    }

    /// The plan reclassified with each hard or tempo step at the zone it actually reached, or `nil`
    /// when the plan can't be laid out on the timeline or there is no heart rate to check it with.
    private func verify(
        _ activity: Activity,
        workout: StructuredWorkout,
        athlete: AthleteProfile,
        plannedClassifier: PlannedIntensityClassifier,
        performedClassifier: PerformedIntensityClassifier
    ) -> Verification? {
        guard let settings = athlete.heartRateZoneSettings(asOf: activity.start) else { return nil }
        let zoneModel = HeartRateZoneModel(settings: settings)
        guard let boundaries = TimeInZoneBuilder.zoneBoundaries(zoneModel) else { return nil }

        let steps = plannedClassifier.plannedSteps(workout, athlete: athlete)
        guard !steps.isEmpty, steps.allSatisfy(\.hasFixedDuration) else { return nil }

        let series = performedClassifier.effortSeries(for: activity, settings: settings)
        guard !series.isEmpty else { return nil }

        var qualitySeconds: TimeInterval = 0
        var verifiedSeconds: TimeInterval = 0
        var verifiedSteps: [PlannedIntensityClassifier.PlannedStep] = []
        for step in steps {
            guard !step.isEdge, step.zone >= 3 else {
                verifiedSteps.append(step)
                continue
            }
            qualitySeconds += step.seconds

            let efforts = effort(in: series, of: activity, from: step.offset, to: step.offset + step.seconds)
            guard Double(efforts.count) * PerformedIntensityClassifier.gridSeconds >= Self.stepMinimumCoverage * step.seconds else {
                verifiedSteps.append(step)
                continue
            }
            verifiedSeconds += step.seconds

            let reached = TimeInZoneBuilder.zone(
                for: zoneModel.deltaHRRatio(for: Self.percentile(Self.stepEffortPercentile, of: efforts)),
                boundaries: boundaries
            )
            verifiedSteps.append(step.at(zone: min(step.zone, reached)))
        }

        return Verification(
            assessment: plannedClassifier.assess(steps: verifiedSteps, zone: \.countedZone),
            verifiedShare: qualitySeconds > 0 ? verifiedSeconds / qualitySeconds : 1
        )
    }

    /// The effort values, in bpm, that fall between `lower` and `upper` seconds after the activity's start.
    private func effort(
        in series: [PerformedIntensityClassifier.EffortSeries],
        of activity: Activity,
        from lower: TimeInterval,
        to upper: TimeInterval
    ) -> [Double] {
        var values: [Double] = []
        for run in series {
            let runOffset = run.start.timeIntervalSince(activity.start)
            for (index, bpm) in run.bpm.enumerated() {
                let time = runOffset + Double(index) * PerformedIntensityClassifier.gridSeconds
                if time >= lower, time < upper { values.append(bpm) }
            }
        }
        return values
    }

    private static func percentile(_ fraction: Double, of values: [Double]) -> Double {
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded(.down))
        return sorted[index]
    }
}

extension PlannedIntensityClassifier.PlannedStep {
    /// This step with its zone replaced, e.g. by the zone it was actually performed in.
    func at(zone: Int) -> PlannedIntensityClassifier.PlannedStep {
        PlannedIntensityClassifier.PlannedStep(
            offset: offset,
            seconds: seconds,
            kind: kind,
            zone: zone,
            isExplicit: isExplicit,
            hasFixedDuration: hasFixedDuration,
            isOpen: isOpen
        )
    }
}

extension IntensityCategory {
    /// This category moved one level towards `target`, or unchanged if already there.
    func moved(toward target: IntensityCategory) -> IntensityCategory {
        if target > self { return IntensityCategory(rawValue: rawValue + 1) ?? self }
        if target < self { return IntensityCategory(rawValue: rawValue - 1) ?? self }
        return self
    }
}
