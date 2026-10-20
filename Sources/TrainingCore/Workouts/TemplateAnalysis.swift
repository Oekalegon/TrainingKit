import Foundation

/// What a ``WorkoutTemplate`` contains, derived from its blocks and the ranges of its parameters
/// (MVP5-118).
///
/// A *hard work step* is a ``StepKind/work`` step aimed at heart-rate zone 3 or higher, or at an RPE of
/// 7 or more. Steps with another target (pace, power, a heart-rate range) or none are not counted
/// as hard. Every range is over the values the template's parameters can take: a parameter's own
/// `range`, or its default when it has none. A distance step is timed with the athlete's pace model,
/// an open step with the default open-step duration, see ``WorkoutDurationEstimator``.
///
/// The analysis works the same for the built-in templates and the athlete's own.
public struct TemplateAnalysis: Sendable, Codable, Hashable {
    /// The kind of activity the template is for.
    public let sport: Sport
    /// The template's tag, or `nil` if untagged.
    public let sessionType: SessionType?
    /// Whether the template is archived.
    public let isArchived: Bool
    /// The shortest and longest hard work step the parameters can produce, in seconds; `nil` when the
    /// template has no hard work step.
    public let workLength: ClosedRange<TimeInterval>?
    /// The fewest and most hard work steps the parameters can produce (repetitions counted);
    /// `0...0` when there are none.
    public let workCount: ClosedRange<Int>
    /// The total time in hard work steps, in seconds, over all parameter values.
    public let workSeconds: ClosedRange<TimeInterval>
    /// The total duration of the session, in seconds, over all parameter values.
    public let duration: ClosedRange<TimeInterval>

    /// Whether the template has any hard work step.
    public var hasHardWork: Bool { workLength != nil }

    /// Creates an analysis.
    ///
    /// - Parameters:
    ///   - sport: The kind of activity the template is for.
    ///   - sessionType: The template's tag, if any.
    ///   - isArchived: Whether the template is archived.
    ///   - workLength: The shortest and longest hard work step in seconds, or `nil` for none.
    ///   - workCount: The fewest and most hard work steps.
    ///   - workSeconds: The total hard work time in seconds.
    ///   - duration: The total session duration in seconds.
    public init(
        sport: Sport, sessionType: SessionType?, isArchived: Bool, workLength: ClosedRange<TimeInterval>?,
        workCount: ClosedRange<Int>, workSeconds: ClosedRange<TimeInterval>, duration: ClosedRange<TimeInterval>
    ) {
        self.sport = sport
        self.sessionType = sessionType
        self.isArchived = isArchived
        self.workLength = workLength
        self.workCount = workCount
        self.workSeconds = workSeconds
        self.duration = duration
    }
}

extension WorkoutTemplate {
    /// The values with each parameter at the low or the high end of its range (its default if it has none).
    fileprivate func extremeValues(high: Bool) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: parameters.map { parameter in
            (parameter.key, parameter.range.map { high ? $0.upperBound : $0.lowerBound } ?? parameter.defaultValue)
        })
    }

    /// Analyses what the template contains.
    ///
    /// Durations come from instantiating the template with every parameter at the low end of its
    /// range, and at the high end. Every step's length grows with its parameters, so the two bound
    /// everything the template can make.
    ///
    /// - Parameters:
    ///   - athlete: Supplies the pace model that times distance steps.
    ///   - estimator: Times open steps; defaults to ``WorkoutDurationEstimator``'s default.
    /// - Returns: The template's ``TemplateAnalysis``.
    /// - Throws: Whatever `instantiate(values:)` throws.
    public func analysis(
        athlete: AthleteProfile, estimator: WorkoutDurationEstimator = WorkoutDurationEstimator()
    ) throws(WorkoutTemplateError) -> TemplateAnalysis {
        struct Measure {
            var lengths: [TimeInterval] = []
            var count = 0
            var workSeconds: TimeInterval = 0
            var duration: TimeInterval = 0
        }
        func measure(_ values: [String: Double]) throws(WorkoutTemplateError) -> Measure {
            let workout = try instantiate(values: values)
            var result = Measure()
            for block in workout.blocks {
                for step in block.steps {
                    let seconds = estimator.duration(for: step, athlete: athlete)
                    result.duration += seconds * Double(block.repetitions)
                    if step.isHardWork {
                        result.lengths.append(seconds)
                        result.count += block.repetitions
                        result.workSeconds += seconds * Double(block.repetitions)
                    }
                }
            }
            return result
        }
        let low = try measure(extremeValues(high: false))
        let high = try measure(extremeValues(high: true))
        let lengths = low.lengths.min().flatMap { shortest in high.lengths.max().map { shortest...max(shortest, $0) } }
        return TemplateAnalysis(
            sport: sport, sessionType: sessionType, isArchived: isArchived, workLength: lengths,
            workCount: min(low.count, high.count)...max(low.count, high.count),
            workSeconds: min(low.workSeconds, high.workSeconds)...max(low.workSeconds, high.workSeconds),
            duration: min(low.duration, high.duration)...max(low.duration, high.duration)
        )
    }
}

extension IntensityTarget? {
    /// Whether the target makes a work step hard: heart-rate zone 3 or higher, or an RPE of 7 or more.
    var isHardEffort: Bool {
        switch self {
        case .heartRateZone(let zone): zone >= 3
        case .rpe(let rpe): rpe >= 7
        default: false
        }
    }
}

extension WorkoutStep {
    /// Whether this is a hard work step, see ``TemplateAnalysis``.
    var isHardWork: Bool { kind == .work && target.isHardEffort }
}

extension TemplateStep {
    /// Whether this is a hard work step, see ``TemplateAnalysis``.
    var isHardWork: Bool { kind == .work && target.isHardEffort }
}
