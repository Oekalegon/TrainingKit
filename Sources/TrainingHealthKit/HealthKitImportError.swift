#if canImport(HealthKit)
/// Errors thrown by ``HealthKitActivityImporter/importActivities(since:)``.
public enum HealthKitImportError: Error, Sendable {
    /// The `ImportAnchor` passed in didn't decode as an `HKQueryAnchor` — e.g. it was produced by
    /// a different importer, or its `data` was corrupted in storage.
    case corruptAnchor
}
#endif
