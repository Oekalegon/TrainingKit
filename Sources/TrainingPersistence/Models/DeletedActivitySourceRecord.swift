import TrainingCore
import Foundation
import SwiftData

/// A tombstone for an ``ActivitySource`` removed via ``SwiftDataStore/deleteActivity(id:)``, so a
/// later ``SwiftDataStore/upsert(_:)`` from a re-import doesn't resurrect it under a new id (see
/// ``ActivityStore/tombstonedSources(among:)``, MVP1-64).
///
/// Cleared by `upsert(_:)` itself the moment that source is genuinely re-added — a deliberate
/// manual re-add, or the same source being deleted and re-imported a second time, both start
/// clean rather than staying tombstoned forever.
@Model
public final class DeletedActivitySourceRecord {
    /// The same string key as `ActivityRecord.sourceKey` — see `ActivitySource.persistenceKey`.
    var sourceKey: String = ""
    /// When the tombstone was recorded. Not read by any query; kept for diagnostics only.
    var deletedAt: Date = Date(timeIntervalSince1970: 0)

    init(sourceKey: String, deletedAt: Date) {
        self.sourceKey = sourceKey
        self.deletedAt = deletedAt
    }
}
