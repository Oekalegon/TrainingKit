import Foundation

/// What ``KeyRaceLayout`` did for one secondary race.
public struct KeyRaceAdjustment: Identifiable, Sendable, Codable, Hashable {
    /// What happened to the race.
    public enum Outcome: Sendable, Codable, Hashable {
        /// The race got a taper and a recovery, in micros; compare with the configured lengths to
        /// see whether either was shortened (down to 0) by the start of the layout, the primary
        /// taper or a neighbouring race.
        case applied(taperMicros: Int, recoveryMicros: Int)
        /// The race was not placed, for the reason given.
        case skipped(SkipReason)
    }

    /// Why a secondary race was not placed.
    public enum SkipReason: String, Sendable, Codable, Hashable, CaseIterable {
        /// Race day is before the first micro or after the primary race (which has no micro after
        /// its day).
        case outsideLayout
        /// Race day falls in the primary race's taper.
        case insidePrimaryTaper
        /// Race day is in the same micro as an earlier secondary race, or in one the earlier
        /// race's taper claims.
        case tooCloseToEarlierRace
    }

    /// The secondary race's ID.
    public var id: UUID { raceID }
    /// The secondary race this entry is about.
    public var raceID: UUID
    /// What happened to the race.
    public var outcome: Outcome

    /// Creates an adjustment.
    ///
    /// - Parameters:
    ///   - raceID: The secondary race this entry is about.
    ///   - outcome: What happened to the race.
    public init(raceID: UUID, outcome: Outcome) {
        self.raceID = raceID
        self.outcome = outcome
    }
}
