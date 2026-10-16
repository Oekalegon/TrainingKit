/// What a free ``DaySlot`` allows beyond a plain run, one entry of ``RunAvailability``.
///
/// The defaults describe a slot the athlete has not configured: a long run fits, and no track is
/// at hand. The generator (MVP5-119) reads the options like this:
/// - It puts a long run only on a slot with ``longRunPossible``.
/// - It puts a track session only on a slot with ``trackAvailable``, and falls back to another
///   quality session when there is none. An interval session never requires a track.
public struct SlotOptions: Sendable, Codable, Hashable {
    /// Whether the slot leaves enough time for a long run.
    public var longRunPossible: Bool

    /// Whether the athlete can get to a track in this slot.
    public var trackAvailable: Bool

    /// The options of a slot without stored options: a long run is possible, no track is available.
    public static let `default` = SlotOptions()

    /// Creates the options of a slot.
    ///
    /// - Parameters:
    ///   - longRunPossible: Whether a long run fits in the slot; defaults to `true`.
    ///   - trackAvailable: Whether a track is available in the slot; defaults to `false`.
    public init(longRunPossible: Bool = true, trackAvailable: Bool = false) {
        self.longRunPossible = longRunPossible
        self.trackAvailable = trackAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case longRunPossible, trackAvailable
    }

    /// Decodes the options; a missing field gets its default (`longRunPossible` `true`,
    /// `trackAvailable` `false`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        longRunPossible = try container.decodeIfPresent(Bool.self, forKey: .longRunPossible) ?? true
        trackAvailable = try container.decodeIfPresent(Bool.self, forKey: .trackAvailable) ?? false
    }
}
