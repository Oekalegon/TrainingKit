import Foundation

/// Where a completed ``Activity`` came from, and the key used to dedupe re-imports.
public enum ActivitySource: Sendable, Codable, Hashable {
    /// A HealthKit workout, keyed by its `HKWorkout.uuid`.
    case healthKit(UUID)
    /// A FIT/TCX file import (MVP 2+).
    case fitFile(URL)
    /// Entered directly by the user, with no external source of truth.
    case manual
}
