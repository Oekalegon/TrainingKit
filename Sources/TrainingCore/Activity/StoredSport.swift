/// A sport read from saved data together with the venue an older version stored inside it.
public struct StoredSport: Decodable, Sendable {
    /// The sport.
    public let sport: Sport
    /// The venue a pre-``Venue`` case implied, or `nil`.
    public let legacyVenue: Venue?

    public init(from decoder: Decoder) throws {
        (sport, legacyVenue) = try Sport.decodeLegacy(from: decoder)
    }
}
