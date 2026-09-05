import Foundation

/// Storage contract for training cycles, enforcing nesting and overlap rules on insert.
public protocol CycleStore: Sendable {
    /// All cycles whose `dateRange` intersects `range`.
    func cycles(in range: ClosedRange<Date>) async throws -> [TrainingCycle]

    /// The cycle with this id, if any.
    func cycle(id: UUID) async throws -> TrainingCycle?

    /// Inserts new cycles or replaces existing ones matched by `id`.
    ///
    /// - Throws: ``CycleStoreError/parentNotFound(_:)`` if a cycle's `parentID` doesn't resolve;
    ///   ``CycleStoreError/childOutsideParentRange(child:parent:)`` if a child's `dateRange` isn't
    ///   fully inside its parent's; ``CycleStoreError/overlappingSiblings(_:_:)`` if two cycles
    ///   sharing a `parentID` overlap.
    func upsert(_ cycles: [TrainingCycle]) async throws

    /// Removes the cycle with this id, if any.
    ///
    /// - Throws: ``CycleStoreError/hasChildren(_:)`` if another cycle's `parentID` still
    ///   references this one — delete children before their parent, so no cycle is ever left
    ///   pointing at one that no longer exists.
    func deleteCycle(id: UUID) async throws
}
