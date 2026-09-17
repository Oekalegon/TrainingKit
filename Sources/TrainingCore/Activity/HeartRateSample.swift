import Foundation

/// A single heart-rate reading at a point in time during an ``Activity``.
public struct HeartRateSample: Sendable, Codable, Hashable {
    /// When this reading was taken.
    public let time: Date
    /// Heart rate in beats per minute.
    public let bpm: Double

    /// Creates a heart-rate sample.
    ///
    /// - Parameters:
    ///   - time: When this reading was taken.
    ///   - bpm: Heart rate in beats per minute.
    public init(time: Date, bpm: Double) {
        self.time = time
        self.bpm = bpm
    }
}
