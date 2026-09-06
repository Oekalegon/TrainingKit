/// Storage contract for the athlete's profile and the incremental-import cursor.
public protocol AthleteStore: Sendable {
    /// The stored athlete profile, if one has been created yet.
    func athleteProfile() async throws -> AthleteProfile?

    /// Replaces the stored athlete profile.
    ///
    /// Preserves `profile.id` exactly as given — the store never generates or rewrites it. A
    /// caller updating an existing profile should mutate a copy of the value previously returned
    /// by ``athleteProfile()`` rather than constructing a fresh ``AthleteProfile``, or the
    /// athlete's identity will silently change (``AthleteProfile/id`` defaults to a new random
    /// `UUID` when omitted), breaking any external mapping — e.g. a multi-athlete roster — keyed
    /// on it.
    func save(_ profile: AthleteProfile) async throws

    /// The persisted ``ImportAnchor`` from the last successful ``ActivityImporting`` run, if any.
    func importAnchor() async throws -> ImportAnchor?

    /// Replaces the persisted import anchor; `nil` clears it, forcing the next import to be a full
    /// one.
    func saveImportAnchor(_ anchor: ImportAnchor?) async throws
}
