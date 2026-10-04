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
}
