import Foundation

/// Cycles laid out around the key races, with what happened to each secondary race.
public struct KeyRaceCycles: Sendable, Codable, Hashable {
    /// The macro, meso and micro cycles, in the order ``CycleLayoutBuilder/layout(from:to:macro:meso:athlete:)`` gives.
    public var cycles: [TrainingCycle]
    /// One entry per secondary race, in date order.
    public var adjustments: [KeyRaceAdjustment]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - cycles: The macro, meso and micro cycles.
    ///   - adjustments: One entry per secondary race, in date order.
    public init(cycles: [TrainingCycle], adjustments: [KeyRaceAdjustment]) {
        self.cycles = cycles
        self.adjustments = adjustments
    }
}
