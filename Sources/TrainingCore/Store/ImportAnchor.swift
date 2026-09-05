import Foundation

/// An opaque cursor for an incremental import, persisted via ``AthleteStore`` between runs.
///
/// `TrainingCore` never interprets the bytes — an importer (e.g. `HealthKitActivityImporter` in
/// `TrainingHealthKit`) archives whatever platform-specific cursor it needs (an `HKQueryAnchor`,
/// for HealthKit) into `data` and hands it back unchanged on the next call.
public struct ImportAnchor: Sendable, Codable, Hashable {
    /// The archived cursor bytes, meaningful only to the importer that produced them.
    public let data: Data

    /// Creates an import anchor.
    ///
    /// - Parameter data: The archived cursor bytes.
    public init(data: Data) {
        self.data = data
    }
}
