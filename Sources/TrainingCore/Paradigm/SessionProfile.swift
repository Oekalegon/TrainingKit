import Foundation

/// What a phase asks of one session, as data a paradigm carries (MVP5-118): "intervals with work
/// lengths between 3 and 5 minutes", "a long run", "easy aerobic".
///
/// A profile is a request, not a planned session (that is ``PlanSession``). ``TemplateFitter``
/// matches it to a library template. Only the fields set are asked for: a profile with just a
/// ``sessionType`` accepts any template of that type.
///
/// Units: durations in seconds, ``raceTargetFraction`` a fraction of the race target (0.9 is 90 %).
public struct SessionProfile: Sendable, Codable, Hashable {
    /// The broad kind of session wanted; a template must carry this tag, see ``WorkoutTemplate/sessionType``.
    public var sessionType: SessionType
    /// The wanted length of a hard work step, in seconds, or `nil` for no requirement. A template
    /// qualifies when the work lengths its parameters can produce, ``TemplateAnalysis/workLength``,
    /// overlap this range.
    public var workLength: ClosedRange<TimeInterval>?
    /// The wanted number of hard work steps, or `nil` for no requirement. A template qualifies when
    /// ``TemplateAnalysis/workCount`` overlaps it.
    public var workCount: ClosedRange<Int>?
    /// The intensity of the work as a fraction of the race target (race pace, say), or `nil`. Data
    /// only: it is not used for matching; ``StepTargetResolver`` turns it into step targets (MVP5-122).
    public var raceTargetFraction: Double?
    /// The intensity in the last micro of the phase, as a fraction of the race target, or `nil` to keep
    /// ``raceTargetFraction`` all phase. The fraction moves linearly from ``raceTargetFraction`` in the
    /// first micro to this one in the last, see ``progressedRaceTargetFraction(microIndex:of:)``; it has
    /// no effect without a ``raceTargetFraction``.
    public var endRaceTargetFraction: Double?

    /// Creates a profile.
    ///
    /// - Parameters:
    ///   - sessionType: The broad kind of session wanted.
    ///   - workLength: The wanted length of a hard work step, in seconds; defaults to `nil`. A range
    ///     with a negative or non-finite bound is dropped to `nil`.
    ///   - workCount: The wanted number of hard work steps; defaults to `nil`. A range with a negative
    ///     lower bound is dropped to `nil`.
    ///   - raceTargetFraction: The work intensity as a fraction of the race target; defaults to `nil`.
    ///     A value that is not positive and finite is dropped to `nil`.
    ///   - endRaceTargetFraction: The fraction in the phase's last micro; defaults to `nil` (no drift).
    ///     A value that is not positive and finite is dropped to `nil`.
    public init(
        sessionType: SessionType,
        workLength: ClosedRange<TimeInterval>? = nil,
        workCount: ClosedRange<Int>? = nil,
        raceTargetFraction: Double? = nil,
        endRaceTargetFraction: Double? = nil
    ) {
        self.sessionType = sessionType
        self.workLength = workLength.flatMap { $0.lowerBound.isFinite && $0.upperBound.isFinite && $0.lowerBound >= 0 ? $0 : nil }
        self.workCount = workCount.flatMap { $0.lowerBound >= 0 ? $0 : nil }
        self.raceTargetFraction = raceTargetFraction.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.endRaceTargetFraction = endRaceTargetFraction.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    /// The race-target fraction for micro `index` of `count` micros of a phase: it steps linearly from
    /// ``raceTargetFraction`` in the first micro to ``endRaceTargetFraction`` in the last, so a fast
    /// quality that starts at 1.14 and ends at 1.06 gets 1.10 in the middle of a three-micro phase.
    ///
    /// Without an end fraction it is ``raceTargetFraction`` itself, and `nil` without a
    /// ``raceTargetFraction``. A phase of one micro uses the start.
    ///
    /// - Parameters:
    ///   - index: The micro's position in its phase, 0 for the first. Clamped to `0..<count`.
    ///   - count: The number of micros in the phase.
    public func progressedRaceTargetFraction(microIndex index: Int, of count: Int) -> Double? {
        guard let start = raceTargetFraction else { return nil }
        guard let end = endRaceTargetFraction, count > 1 else { return start }
        let position = Double(min(max(index, 0), count - 1)) / Double(count - 1)
        return start + (end - start) * position
    }

    /// The work length for micro `index` of `count` micros of a phase, in seconds: it steps linearly
    /// from the low end of ``workLength`` in the first micro to the high end in the last (parameter
    /// progression).
    ///
    /// The result is the midpoint of the range for a phase of one micro, and `nil` for a profile
    /// without a ``workLength``. The micro's length in days does not change it; the volume does
    /// that, through the repetitions ``TemplateFitter`` solves.
    ///
    /// - Parameters:
    ///   - index: The micro's position in its phase, 0 for the first. Clamped to `0..<count`.
    ///   - count: The number of micros in the phase.
    public func progressedWorkLength(microIndex index: Int, of count: Int) -> TimeInterval? {
        guard let workLength else { return nil }
        guard count > 1 else { return (workLength.lowerBound + workLength.upperBound) / 2 }
        let position = Double(min(max(index, 0), count - 1)) / Double(count - 1)
        return workLength.lowerBound + (workLength.upperBound - workLength.lowerBound) * position
    }

    private enum CodingKeys: String, CodingKey {
        case sessionType, workLength, workCount, raceTargetFraction, endRaceTargetFraction
    }

    /// Decodes a profile; everything but `sessionType` is optional. A range that is invalid reads as
    /// absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionType: try container.decode(SessionType.self, forKey: .sessionType),
            workLength: try? container.decodeIfPresent(ClosedRange<TimeInterval>.self, forKey: .workLength),
            workCount: try? container.decodeIfPresent(ClosedRange<Int>.self, forKey: .workCount),
            raceTargetFraction: try? container.decodeIfPresent(Double.self, forKey: .raceTargetFraction),
            endRaceTargetFraction: try? container.decodeIfPresent(Double.self, forKey: .endRaceTargetFraction)
        )
    }
}
