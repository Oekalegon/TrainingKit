import TrainingCore
import Foundation
import SwiftData

/// Records that the activity `joinID` (an ``ActivityRecord`` like any other) stands in for a set of
/// component activities recorded in pieces — see ``ActivityStore/saveJoin(_:components:replacing:)``.
///
/// Kept in its own table rather than as a flag on each component's ``ActivityRecord``, because
/// `upsert(_:)` rewrites a component's whole record when a re-import redelivers it, which would
/// silently clear a flag and un-hide the piece. This table isn't touched by `upsert(_:)`.
@Model
public final class ActivityJoinRecord {
    /// The joined activity's id (an ``ActivityRecord/id``).
    var joinID: UUID = UUID()
    /// The JSON-encoded `[UUID]` of component activity ids.
    var componentsPayload: Data = Data()

    init(joinID: UUID, componentsPayload: Data) {
        self.joinID = joinID
        self.componentsPayload = componentsPayload
    }
}

extension ActivityJoinRecord {
    /// Creates a join record by encoding `componentIDs`.
    convenience init(joinID: UUID, componentIDs: [UUID]) throws {
        self.init(joinID: joinID, componentsPayload: try PersistenceCoding.encode(componentIDs))
    }

    /// The component ids decoded from `componentsPayload`.
    func componentIDs() throws -> [UUID] {
        try PersistenceCoding.decode([UUID].self, from: componentsPayload)
    }
}
