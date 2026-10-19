import Foundation

/// Micros laid out around the key races, with what happened to each secondary race.
public struct KeyRaceMicrocycles: Sendable, Codable, Hashable {
    /// The micros, oldest first.
    public var micros: [Microcycle]
    /// One entry per secondary race, in date order.
    public var adjustments: [KeyRaceAdjustment]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - micros: The micros, oldest first.
    ///   - adjustments: One entry per secondary race, in date order.
    public init(micros: [Microcycle], adjustments: [KeyRaceAdjustment]) {
        self.micros = micros
        self.adjustments = adjustments
    }
}
