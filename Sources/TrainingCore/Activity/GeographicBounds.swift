/// The geographic bounding box an ``Activity`` took place within.
///
/// Deliberately not a route: `TrainingCore` never stores GPS trackpoints (they're large, mostly
/// used for map display rather than any load/fitness math, and cheaply re-fetchable from the
/// original source — HealthKit's route API, a FIT file — whenever a map view actually needs
/// them). This bounding box is enough to answer "roughly where did this happen" without that cost.
public struct GeographicBounds: Sendable, Codable, Hashable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }
}
