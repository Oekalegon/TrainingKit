import Foundation

/// One run placed on a day and day part by ``DayAssigner``.
public struct DayAssignment: Sendable, Hashable {
    /// The calendar day of the run.
    public let day: Date
    /// The free part of that day the run is in.
    public let slot: DaySlot
    /// The kind of run.
    public let runType: RunType

    /// Creates a day assignment.
    ///
    /// - Parameters:
    ///   - day: The calendar day of the run.
    ///   - slot: The free part of that day the run is in.
    ///   - runType: The kind of run.
    public init(day: Date, slot: DaySlot, runType: RunType) {
        self.day = day
        self.slot = slot
        self.runType = runType
    }
}
