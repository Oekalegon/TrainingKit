/// Where an activity happens, separate from the ``Sport`` performed: a run is a run whether it's on a
/// treadmill or a trail.
///
/// `nil` wherever a venue is optional means unspecified — compatible with any venue (see
/// ``isCompatible(_:_:)``). WorkoutKit only knows indoor or outdoor, via ``isIndoor``; the surface
/// is for the athlete and for stricter matching.
public enum Venue: Sendable, Hashable {
    /// Indoors, optionally on a specific surface.
    case indoor(IndoorSurface?)
    /// Outdoors, optionally on a specific surface.
    case outdoor(OutdoorSurface?)

    /// An indoor surface.
    public enum IndoorSurface: String, Sendable, Codable, Hashable, CaseIterable {
        case treadmill, track
    }

    /// An outdoor surface.
    public enum OutdoorSurface: String, Sendable, Codable, Hashable, CaseIterable {
        case track, road, trail, offtrail
    }

    /// Whether the venue is indoors.
    public var isIndoor: Bool {
        if case .indoor = self { return true }
        return false
    }

    /// Whether the venue names a surface, not only indoors or outdoors.
    public var hasSurface: Bool {
        switch self {
        case .indoor(let surface): surface != nil
        case .outdoor(let surface): surface != nil
        }
    }

    /// Whether two optional venues can describe the same activity: either is unspecified, or both are
    /// indoors, or both are outdoors. Surfaces don't count — a trail run and a road run are
    /// both outdoor runs; a treadmill run and a trail run aren't the same session.
    public static func isCompatible(_ lhs: Venue?, _ rhs: Venue?) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs.isIndoor == rhs.isIndoor
    }

    /// The venues a plan can choose between for `sport`; empty for a sport without venue variants.
    public static func choices(for sport: Sport) -> [Venue] {
        switch sport {
        case .running:
            [.indoor(.treadmill), .indoor(.track), .outdoor(.road), .outdoor(.track), .outdoor(.trail), .outdoor(.offtrail)]
        case .cycling:
            [.indoor(nil), .outdoor(.road), .outdoor(.trail), .outdoor(.offtrail)]
        default:
            []
        }
    }
}

extension Venue: Codable {
    private enum CodingKeys: String, CodingKey {
        case location, surface
    }

    /// Decodes `{"location": "indoor"|"outdoor", "surface": …}`; an unknown surface reads as none
    /// rather than failing, so a newer file still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(String.self, forKey: .location)
        switch location {
        case "indoor":
            self = .indoor(try? container.decodeIfPresent(IndoorSurface.self, forKey: .surface))
        case "outdoor":
            self = .outdoor(try? container.decodeIfPresent(OutdoorSurface.self, forKey: .surface))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .location, in: container, debugDescription: "Unknown venue location \(location)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .indoor(let surface):
            try container.encode("indoor", forKey: .location)
            try container.encodeIfPresent(surface, forKey: .surface)
        case .outdoor(let surface):
            try container.encode("outdoor", forKey: .location)
            try container.encodeIfPresent(surface, forKey: .surface)
        }
    }
}
