import Foundation

/// Errors thrown by ``CycleStore/upsert(_:)`` when a nesting or overlap rule is violated.
public enum CycleStoreError: Error, Sendable, Equatable {
    /// A cycle references a `parentID` that doesn't exist in the store or the same upsert batch.
    case parentNotFound(UUID)
    /// A child cycle's `dateRange` isn't fully contained within its parent's.
    case childOutsideParentRange(child: UUID, parent: UUID)
    /// Two cycles sharing the same `parentID` have overlapping `dateRange`s.
    case overlappingSiblings(UUID, UUID)
}
