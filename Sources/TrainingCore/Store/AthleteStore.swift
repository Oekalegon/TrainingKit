/// Storage contract for the athlete's profile and the incremental-import cursor.
public protocol AthleteStore: Sendable {
    /// The stored athlete profile, if one has been created yet.
    func athleteProfile() async throws -> AthleteProfile?

    /// Replaces the stored athlete profile.
    func save(_ profile: AthleteProfile) async throws

    /// The persisted ``ImportAnchor`` from the last successful ``ActivityImporting`` run, if any.
    func importAnchor() async throws -> ImportAnchor?

    /// Replaces the persisted import anchor; `nil` clears it, forcing the next import to be a full
    /// one.
    func saveImportAnchor(_ anchor: ImportAnchor?) async throws
}
