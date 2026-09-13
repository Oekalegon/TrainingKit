import Foundation

/// A pair of ``Activity``s whose ``Activity/dateRange``s overlap without either one fully
/// containing the other.
///
/// A contained pair (e.g. a triathlon leg logged as its own activity nested inside a
/// multisport-watch summary activity) is expected, not a warning — see
/// ``ActivityOverlapChecker/findOverlaps(in:)``.
public struct ActivityOverlap: Sendable, Hashable {
    /// One of the two overlapping activities' ids.
    public let first: UUID
    /// The other overlapping activity's id.
    public let second: UUID
    /// The time span the two activities have in common.
    public let overlappingRange: ClosedRange<Date>

    /// Creates an activity overlap.
    ///
    /// - Parameters:
    ///   - first: One of the two overlapping activities' ids.
    ///   - second: The other overlapping activity's id.
    ///   - overlappingRange: The time span the two activities have in common.
    public init(first: UUID, second: UUID, overlappingRange: ClosedRange<Date>) {
        self.first = first
        self.second = second
        self.overlappingRange = overlappingRange
    }
}
