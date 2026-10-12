/// The kind of activity performed, used to select load calculators and match completed
/// activities to planned ones.
///
/// Where it happens (indoors, a trail, a track) is a separate ``Venue``, carried next to the sport
/// by ``Activity``, ``StructuredWorkout`` and ``WorkoutTemplate``.
public enum Sport: Sendable, Hashable {
    case running
    case cycling
    case swimming
    case strength
    /// Core-focused strength work (e.g. HealthKit's `coreTraining`), tracked separately from
    /// general ``strength`` training since it targets a distinct muscle group and training goal.
    case coreStrengthTraining
    case walking
    case rowing
    case hiking
    case other(String)

    /// Whether `self` and `other` should be treated as the same kind of activity for
    /// ``ActivityOverlapChecker``'s same-sport checks, even when they aren't the exact same case —
    /// e.g. a hike and a walk.
    ///
    /// The venues, when both sides give one, must also agree on indoors versus outdoors (see
    /// ``Venue/isCompatible(_:_:)``): an indoor run and a trail run are different sessions, while a
    /// run with no venue matches either.
    ///
    /// - Parameters:
    ///   - other: The sport to compare with.
    ///   - venue: `self`'s venue, if known.
    ///   - otherVenue: `other`'s venue, if known.
    public func isSameFamily(as other: Sport, venue: Venue?, otherVenue: Venue?) -> Bool {
        guard Venue.isCompatible(venue, otherVenue) else { return false }
        if self == other { return true }
        let hikingOrWalking: Set<Sport> = [.hiking, .walking]
        return hikingOrWalking.contains(self) && hikingOrWalking.contains(other)
    }
}

extension Sport: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct OtherKey: CodingKey {
        var stringValue: String { "_0" }
        var intValue: Int? { nil }
        init() {}
        init?(stringValue: String) { nil }
        init?(intValue: Int) { nil }
    }

    /// The sport and, for data saved before ``Venue`` existed, the venue its old case implied
    /// (`indoorRunning`, `outdoorRunning`).
    static func decodeLegacy(from decoder: Decoder) throws -> (sport: Sport, venue: Venue?) {
        let container = try decoder.container(keyedBy: Key.self)
        guard let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty sport"))
        }
        switch key.stringValue {
        case "running": return (.running, nil)
        case "indoorRunning": return (.running, .indoor(nil))
        case "outdoorRunning": return (.running, .outdoor(nil))
        case "cycling": return (.cycling, nil)
        case "swimming": return (.swimming, nil)
        case "strength": return (.strength, nil)
        case "coreStrengthTraining": return (.coreStrengthTraining, nil)
        case "walking": return (.walking, nil)
        case "rowing": return (.rowing, nil)
        case "hiking": return (.hiking, nil)
        case "other":
            let nested = try container.nestedContainer(keyedBy: OtherKey.self, forKey: key)
            return (.other(try nested.decode(String.self, forKey: OtherKey())), nil)
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown sport \(key.stringValue)")
            )
        }
    }

    /// Decodes a sport, reading the pre-``Venue`` `indoorRunning`/`outdoorRunning` as ``running``.
    public init(from decoder: Decoder) throws {
        self = try Self.decodeLegacy(from: decoder).sport
    }

    /// Encodes in the shape the compiler synthesized before this type had custom coding, so data
    /// stays readable by older versions.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        let name: String
        switch self {
        case .running: name = "running"
        case .cycling: name = "cycling"
        case .swimming: name = "swimming"
        case .strength: name = "strength"
        case .coreStrengthTraining: name = "coreStrengthTraining"
        case .walking: name = "walking"
        case .rowing: name = "rowing"
        case .hiking: name = "hiking"
        case .other(let label):
            var nested = container.nestedContainer(keyedBy: OtherKey.self, forKey: Key(stringValue: "other"))
            try nested.encode(label, forKey: OtherKey())
            return
        }
        _ = container.nestedContainer(keyedBy: OtherKey.self, forKey: Key(stringValue: name))
    }
}
