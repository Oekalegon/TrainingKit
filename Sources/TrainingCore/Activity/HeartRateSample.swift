import Foundation

/// A single heart-rate reading at a point in time during an ``Activity``.
public struct HeartRateSample: Sendable, Codable, Hashable {
    public let time: Date
    public let bpm: Double

    public init(time: Date, bpm: Double) {
        self.time = time
        self.bpm = bpm
    }
}
