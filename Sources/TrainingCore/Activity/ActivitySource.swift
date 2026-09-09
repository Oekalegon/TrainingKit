import Foundation

/// Where a completed ``Activity`` came from, and the key used to dedupe re-imports.
public enum ActivitySource: Sendable, Codable, Hashable {
    /// A HealthKit workout, keyed by its `HKWorkout.uuid`.
    case healthKit(UUID)
    /// A FIT/TCX file import (MVP 2+).
    case fitFile(URL)
    /// Entered directly by the user, with no external source of truth.
    case manual
    /// Entered only to exercise the app during development/QA — tag activities created this way
    /// with `.testing` so they're easy to identify and remove without touching real
    /// HealthKit-imported or manually-logged training history.
    case testing

    /// Whether this source carries a stable external identity (a HealthKit UUID, a file path)
    /// that lets a re-import find "the same activity" again.
    ///
    /// `.manual` and `.testing` entries have no such identity — each one is independent, so
    /// ``ActivityStore/upsert(_:)`` never matches or dedupes them against another entry of the
    /// same case.
    public var hasNaturalKey: Bool {
        switch self {
        case .healthKit, .fitFile:
            return true
        case .manual, .testing:
            return false
        }
    }
}
