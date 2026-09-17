import Foundation

/// The outcome of one ``ActivityImporting/importActivities(since:)`` run.
public struct ImportResult: Sendable {
    /// Activities added or updated since the anchor passed in; ready for ``ActivityStore/upsert(_:)``.
    public let upserted: [Activity]
    /// Sources removed at the origin since the anchor passed in; ready for
    /// ``ActivityStore/deleteActivity(source:)``.
    public let deletedSources: [ActivitySource]
    /// The cursor to persist and pass as `since` on the next call, or `nil` if the importer doesn't
    /// support incremental import.
    public let anchor: ImportAnchor?

    /// Creates an import result.
    ///
    /// - Parameters:
    ///   - upserted: Activities added or updated since the anchor passed in.
    ///   - deletedSources: Sources removed at the origin since the anchor passed in.
    ///   - anchor: The cursor to persist for the next call, or `nil` if unsupported.
    public init(upserted: [Activity], deletedSources: [ActivitySource], anchor: ImportAnchor?) {
        self.upserted = upserted
        self.deletedSources = deletedSources
        self.anchor = anchor
    }
}
