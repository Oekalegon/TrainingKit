import Foundation

/// Errors thrown by ``CycleStore/upsert(_:)`` and ``CycleStore/deleteCycle(id:)`` when a nesting,
/// overlap, or orphaning rule is violated.
public enum CycleStoreError: Error, Sendable, Equatable {
    /// A cycle references a `parentID` that doesn't exist in the store or the same upsert batch.
    case parentNotFound(UUID)
    /// A child cycle's `dateRange` isn't fully contained within its parent's.
    case childOutsideParentRange(child: UUID, parent: UUID)
    /// Two cycles sharing the same `parentID` have overlapping `dateRange`s.
    case overlappingSiblings(UUID, UUID)
    /// The cycle being deleted still has children referencing it via `parentID`; delete those
    /// first, or reassign/remove their `parentID`, so no cycle is left pointing at a deleted parent.
    case hasChildren(UUID)
}
