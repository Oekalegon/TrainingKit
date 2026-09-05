/// Storage contract for the athlete's profile.
///
/// Kept minimal for now — the design doc also anticipates HealthKit import anchors being
/// persisted here (§5.1), but that shape depends on `TrainingHealthKit`'s not-yet-built
/// `ImportAnchor` type; adding a generic blob-storage API ahead of that risks guessing wrong.
public protocol AthleteStore: Sendable {
    /// The stored athlete profile, if one has been created yet.
    func athleteProfile() async throws -> AthleteProfile?

    /// Replaces the stored athlete profile.
    func save(_ profile: AthleteProfile) async throws
}
