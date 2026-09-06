import Foundation

/// Validates the nesting/overlap rules ``CycleStore`` promises on ``CycleStore/upsert(_:)``.
///
/// Factored out of any single store implementation so every conforming store (``InMemoryStore``
/// here, `SwiftDataStore` in `TrainingPersistence`) enforces exactly the same rule rather than
/// each reimplementing it and silently drifting apart.
public enum CycleNestingValidator {
    /// Validates `cycles` against `existing` (every cycle already in the store, keyed by id) plus
    /// each other, so a parent and its children can be upserted together in one call regardless of
    /// which order they appear in `cycles` — a child listed before its parent in the array is
    /// still resolved correctly, since `existing` is overlaid with the entire incoming batch before
    /// any cycle is checked.
    ///
    /// - Parameters:
    ///   - cycles: The cycles being upserted.
    ///   - existing: Every cycle currently in the store, keyed by id.
    /// - Throws: ``CycleStoreError/parentNotFound(_:)`` if a cycle's `parentID` doesn't resolve in
    ///   `existing` or `cycles`; ``CycleStoreError/childOutsideParentRange(child:parent:)`` if a
    ///   child's `dateRange` isn't fully inside its parent's; ``CycleStoreError/overlappingSiblings(_:_:)``
    ///   if two cycles sharing a `parentID` overlap.
    public static func validate(_ cycles: [TrainingCycle], existing: [UUID: TrainingCycle]) throws(CycleStoreError) {
        var workingSet = existing
        for cycle in cycles {
            workingSet[cycle.id] = cycle
        }

        for cycle in cycles {
            if let parentID = cycle.parentID {
                guard let parent = workingSet[parentID] else {
                    throw .parentNotFound(parentID)
                }
                guard parent.dateRange.lowerBound <= cycle.dateRange.lowerBound,
                      cycle.dateRange.upperBound <= parent.dateRange.upperBound
                else {
                    throw .childOutsideParentRange(child: cycle.id, parent: parentID)
                }
            }

            let siblings = workingSet.values.filter { $0.parentID == cycle.parentID && $0.id != cycle.id }
            for sibling in siblings where sibling.dateRange.overlaps(cycle.dateRange) {
                throw .overlappingSiblings(cycle.id, sibling.id)
            }
        }
    }
}
