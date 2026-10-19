import Foundation

/// The intensity a race's specific-phase work is aimed at (MVP5-114): usually the pace the athlete
/// wants to hold on race day.
///
/// It is stored on ``Race/specificPhaseTarget``. Nothing reads it yet: resolving it into the
/// intensity of a step (MVP5-122) and the generator that uses it come later. A race without a target
/// is stored as `nil`.
///
/// Build a value with the cases, then call ``validate()`` to reject nonsense; decoding validates too.
public enum SpecificPhaseTarget: Sendable, Codable, Hashable {
    /// A goal pace for the race distance, in seconds per kilometer (a 4:00/km pace is `240`).
    ///
    /// The value must be finite and above zero. Showing it per mile is a display matter.
    case pace(secondsPerKilometer: Double)
    /// A target heart-rate range, in beats per minute; give the same bound twice for a single value.
    ///
    /// Both bounds must be finite and above zero.
    case heartRate(beatsPerMinute: ClosedRange<Double>)
    /// A perceived effort on the Borg CR10 scale, from 1 to 10.
    case perceivedEffort(Int)
    /// A pace to be predicted from the athlete's current fitness.
    ///
    /// A placeholder: no prediction model exists yet, so this only records that the athlete wants
    /// the target worked out rather than set.
    case predictedFromFitness

    /// The lowest and highest valid ``perceivedEffort(_:)`` rating.
    public static let perceivedEffortRange = 1...10

    /// Checks that the value makes sense.
    ///
    /// - Throws: ``SpecificPhaseTargetError/invalidPace`` for a pace that is not finite or not above
    ///   zero, ``SpecificPhaseTargetError/invalidHeartRate`` for a heart rate bound that is not finite
    ///   or not above zero, ``SpecificPhaseTargetError/invalidPerceivedEffort`` for an effort outside
    ///   ``perceivedEffortRange``.
    public func validate() throws {
        switch self {
        case .pace(let seconds):
            guard seconds.isFinite, seconds > 0 else { throw SpecificPhaseTargetError.invalidPace }
        case .heartRate(let range):
            guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound > 0 else {
                throw SpecificPhaseTargetError.invalidHeartRate
            }
        case .perceivedEffort(let rating):
            guard Self.perceivedEffortRange.contains(rating) else { throw SpecificPhaseTargetError.invalidPerceivedEffort }
        case .predictedFromFitness:
            break
        }
    }

    /// Decodes a target and validates it.
    ///
    /// - Throws: A `DecodingError`, or the ``SpecificPhaseTargetError`` ``validate()`` throws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try Self.decodeCases(from: container)
        try validate()
    }

    /// Mirrors the public cases so the synthesized Codable can be reused; keep the two lists in step.
    private enum Cases: Codable {
        case pace(secondsPerKilometer: Double)
        case heartRate(beatsPerMinute: ClosedRange<Double>)
        case perceivedEffort(Int)
        case predictedFromFitness
    }

    private static func decodeCases(from container: any SingleValueDecodingContainer) throws -> SpecificPhaseTarget {
        switch try container.decode(Cases.self) {
        case .pace(let value): .pace(secondsPerKilometer: value)
        case .heartRate(let value): .heartRate(beatsPerMinute: value)
        case .perceivedEffort(let value): .perceivedEffort(value)
        case .predictedFromFitness: .predictedFromFitness
        }
    }

    /// Encodes the target as a single keyed value, one key per kind.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .pace(let value): try container.encode(Cases.pace(secondsPerKilometer: value))
        case .heartRate(let value): try container.encode(Cases.heartRate(beatsPerMinute: value))
        case .perceivedEffort(let value): try container.encode(Cases.perceivedEffort(value))
        case .predictedFromFitness: try container.encode(Cases.predictedFromFitness)
        }
    }
}
