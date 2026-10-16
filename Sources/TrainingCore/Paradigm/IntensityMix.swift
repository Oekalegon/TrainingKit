import Foundation

/// Target shares of planned time per intensity category and per speed level, with a tolerance.
///
/// Used by the ``PlanRule/intensityDistribution`` rule. A share is a fraction of the planned time
/// (0...1) of the sessions in a micro. Only the categories and levels listed are checked: a target
/// of `[.high: 0.2, .low: 0.8]` says nothing about `veryLow`, and the polarized 80/20 split is just
/// that mix. List a category with a share of 0 to forbid it (a base phase of only easy runs).
///
/// Encodes the shares keyed by case name; unknown names are ignored and a missing key means no
/// target, so older payloads keep decoding.
public struct IntensityMix: Sendable, Codable, Hashable {
    /// The target share of planned time per intensity category.
    public var intensityShares: [IntensityCategory: Double]
    /// The target share of planned time per speed level, using each session's ``PlanSession/speed``.
    public var speedShares: [SpeedLevel: Double]
    /// How far an actual share may be from its target, as a fraction (0.05 is five percentage points).
    public var tolerance: Double

    /// Creates a mix.
    ///
    /// - Parameters:
    ///   - intensityShares: The target share of planned time per intensity category (0...1).
    ///   - speedShares: The target share of planned time per speed level (0...1).
    ///   - tolerance: The allowed deviation from a target, as a fraction; defaults to 0.05.
    public init(intensityShares: [IntensityCategory: Double] = [:], speedShares: [SpeedLevel: Double] = [:], tolerance: Double = 0.05) {
        self.intensityShares = intensityShares
        self.speedShares = speedShares
        self.tolerance = tolerance
    }

    private enum CodingKeys: String, CodingKey {
        case intensityShares, speedShares, tolerance
    }

    /// Decodes a mix; every field is optional.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let intensity = try container.decodeIfPresent([String: Double].self, forKey: .intensityShares) ?? [:]
        let speed = try container.decodeIfPresent([String: Double].self, forKey: .speedShares) ?? [:]
        intensityShares = Dictionary(IntensityCategory.allCases.compactMap { category in
            intensity[String(describing: category)].map { (category, $0) }
        }, uniquingKeysWith: { first, _ in first })
        speedShares = Dictionary(SpeedLevel.allCases.compactMap { level in
            speed[level.rawValue].map { (level, $0) }
        }, uniquingKeysWith: { first, _ in first })
        tolerance = try container.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0.05
    }

    /// Encodes the shares keyed by case name.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: intensityShares.map { (String(describing: $0.key), $0.value) }), forKey: .intensityShares)
        try container.encode(Dictionary(uniqueKeysWithValues: speedShares.map { ($0.key.rawValue, $0.value) }), forKey: .speedShares)
        try container.encode(tolerance, forKey: .tolerance)
    }
}
