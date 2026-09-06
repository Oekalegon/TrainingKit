import TrainingCore
import Foundation
import SwiftData

/// The persisted singleton row for the athlete profile and the incremental-import anchor.
///
/// Both fields are optional and independent: the anchor can be saved before a profile ever is
/// (importing activities doesn't require the profile to be set up first), and vice versa. There's
/// exactly one of these rows per store — ``SwiftDataStore`` fetches-or-creates it rather than ever
/// inserting a second. That's still correct for multiple athletes: a host app supporting more than
/// one athlete constructs a separate `ModelContainer` (and thus a separate ``SwiftDataStore``) per
/// athlete, so "one row per store" and "one athlete per store" are the same thing.
///
/// The class is public for the same reason as ``ActivityRecord``: a host app composing its own
/// `Schema`/`ModelContainer` needs to reference it directly. Unlike ``ActivityRecord``, there's no
/// `id` column on this row itself — its identity lives inside the decoded `AthleteProfile.id`/
/// `.name` (accessible via `toProfile()?.id`), not as a queryable SwiftData field, since a host app
/// distinguishes athletes by which store/container it's asking, not by filtering rows within one.
/// `toProfile()`/`update(from:)` are the only public surface.
@Model
public final class AthleteProfileRecord {
    /// The JSON-encoded `AthleteProfile`, or `nil` if none has been saved yet.
    var profilePayload: Data?
    /// The `ImportAnchor.data` from the last successful import, or `nil` if none has been saved yet.
    var importAnchorData: Data?

    init(profilePayload: Data? = nil, importAnchorData: Data? = nil) {
        self.profilePayload = profilePayload
        self.importAnchorData = importAnchorData
    }
}

extension AthleteProfileRecord {
    /// Decodes `profilePayload` back into an `AthleteProfile`, or `nil` if none has been saved yet.
    public func toProfile() throws -> AthleteProfile? {
        try profilePayload.map { try PersistenceCoding.decode(AthleteProfile.self, from: $0) }
    }

    /// Replaces this record's `profilePayload` with `profile`'s.
    ///
    /// - Parameter profile: The profile to update this record from.
    public func update(from profile: AthleteProfile) throws {
        profilePayload = try PersistenceCoding.encode(profile)
    }
}
