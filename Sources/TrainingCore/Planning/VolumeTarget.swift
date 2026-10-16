/// What a ``VolumeTarget`` counts.
public enum VolumeMeasure: String, Sendable, Codable, Hashable, CaseIterable {
    /// Distance covered, in meters.
    case distanceMeters
    /// Time spent training, in seconds.
    case durationSeconds
    /// Training load in TRIMP, the unit of ``TRIMPPlanEstimator``.
    case trimp
}

/// An amount of training in one ``VolumeMeasure``: 60 000 meters, 18 000 seconds or 450 TRIMP.
///
/// The period it applies to is given by the property that holds it, for instance
/// ``PlanPreferences/maxWeeklyVolume`` (per 7 days). The amount is always positive and finite.
public struct VolumeTarget: Sendable, Codable, Hashable {
    /// What the amount counts.
    public let measure: VolumeMeasure

    /// The amount, in meters, seconds or TRIMP according to ``measure``. Positive and finite.
    public let amount: Double

    /// Creates a volume target, or `nil` when `amount` is not a positive, finite number.
    ///
    /// - Parameters:
    ///   - measure: What the amount counts.
    ///   - amount: The amount in the unit of `measure`: meters, seconds or TRIMP.
    public init?(measure: VolumeMeasure, amount: Double) {
        guard amount.isFinite, amount > 0 else { return nil }
        self.measure = measure
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey {
        case measure, amount
    }

    /// Decodes a target; throws when the measure is unknown or the amount is not positive and finite.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let measure = try container.decode(VolumeMeasure.self, forKey: .measure)
        let amount = try container.decode(Double.self, forKey: .amount)
        guard let target = VolumeTarget(measure: measure, amount: amount) else {
            throw DecodingError.dataCorruptedError(
                forKey: .amount, in: container, debugDescription: "Volume must be positive and finite"
            )
        }
        self = target
    }
}
