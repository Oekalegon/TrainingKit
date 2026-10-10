import Foundation

/// Why a calendar export file couldn't be read (MVP2-103).
public enum CalendarImportError: Error, Sendable, Hashable {
    /// The data isn't a calendar export: not JSON, or fields are missing or malformed.
    case unreadable
    /// The file was written with a newer format than this version of the app understands, so
    /// importing it could silently drop or misread fields.
    case unsupportedSchemaVersion(found: Int, supported: Int)
}

/// What a calendar import did, or, for a preview, would do (MVP2-103).
public struct CalendarImportReport: Sendable, Hashable {
    /// Why a planned entry was left out.
    public enum RejectionReason: Sendable, Hashable {
        /// The entry has no steps, as in a file written before steps were exported (MVP2-102), so
        /// no workout can be rebuilt from it.
        case noSteps
        /// A step has a kind or goal this version doesn't know, or a distance step has no distance.
        case invalidStep
        /// The day isn't a valid `yyyy-MM-dd` date.
        case invalidDate
    }

    /// A planned entry that couldn't be imported.
    public struct Rejection: Sendable, Hashable {
        /// The entry's day, as written in the file.
        public let date: String
        /// The entry's name, if it has one.
        public let name: String?
        /// Why it was left out.
        public let reason: RejectionReason
    }

    /// Planned workouts added as new plans.
    public let added: Int
    /// Planned entries skipped because the app already has a plan for the same workout on that
    /// day, so importing the same file twice adds nothing the second time.
    public let skippedDuplicates: Int
    /// Planned entries skipped because their day is before today. Such a plan would only show as
    /// missed and never counts as load, and the export leaves missed plans out for the same reason.
    public let skippedPast: Int
    /// Completed activities in the file, which aren't imported: they come from HealthKit, and the
    /// model can't yet hold an imported load for one without heart-rate data.
    public let skippedCompleted: Int
    /// Planned entries that couldn't be imported.
    public let rejected: [Rejection]
    /// Templates added to the library (MVP2-141), because a plan that was added uses them and the
    /// library had nothing equal.
    public let templatesAdded: Int
    /// Templates in the file that the library already had in an equal form, which the added plans'
    /// workouts were linked to instead of adding another.
    public let templatesLinked: Int
    /// Templates added under a new id, because the library has a different template with the same id.
    /// Counted in addition to ``templatesAdded``'s own, not within it.
    public let templatesCopied: Int
    /// Templates in the file that couldn't be read, or couldn't be stored. Their workouts are rebuilt
    /// from their steps, without a template link.
    public let templatesRejected: Int

    init(
        added: Int, skippedDuplicates: Int, skippedPast: Int, skippedCompleted: Int, rejected: [Rejection],
        templatesAdded: Int = 0, templatesLinked: Int = 0, templatesCopied: Int = 0, templatesRejected: Int = 0
    ) {
        self.added = added
        self.skippedDuplicates = skippedDuplicates
        self.skippedPast = skippedPast
        self.skippedCompleted = skippedCompleted
        self.rejected = rejected
        self.templatesAdded = templatesAdded
        self.templatesLinked = templatesLinked
        self.templatesCopied = templatesCopied
        self.templatesRejected = templatesRejected
    }
}
