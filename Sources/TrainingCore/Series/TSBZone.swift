/// A qualitative classification of Training Stress Balance (``FitnessMetrics/tsb``, CTL − ATL)
/// into named training-state bands — the standard coaching interpretation of TSB (see Joe Friel's
/// *Training Bible* and TrainingPeaks' own Performance Management Chart guidance) for reading
/// freshness/fatigue at a glance rather than as a raw number.
///
/// Boundaries run on `tsb` itself, ascending from most negative (``injuryRisk``, heavy
/// accumulated fatigue) to most positive (``detraining``, fitness now fading from sustained
/// rest).
public enum TSBZone: String, Sendable, Codable, Hashable, CaseIterable {
    /// `tsb < -30`: fatigue is badly outpacing fitness — the classic overreaching zone, with
    /// elevated injury/illness risk if sustained.
    case injuryRisk
    /// `-30 ..< -10`: sustained hard training, building fitness at a normal, tolerable cost.
    case training
    /// `-10 ..< 5`: roughly balanced — fatigue has largely cleared without meaningful fitness
    /// loss, a sustainable zone for maintaining.
    case recovery
    /// `5 ..< 25`: fresh with fitness still largely intact — the taper/race-ready window.
    case race
    /// `tsb >= 25`: rest sustained long enough to start losing fitness, not just fatigue.
    case detraining

    /// The lower bound (inclusive) of each zone, in ascending `tsb` order — the single source of
    /// truth ``init(tsb:)`` switches on, so the boundaries can't drift out of sync with each
    /// other.
    private static let lowerBounds: [(zone: TSBZone, lowerBound: Double)] = [
        (.injuryRisk, -.infinity),
        (.training, -30),
        (.recovery, -10),
        (.race, 5),
        (.detraining, 25),
    ]

    /// Classifies `tsb` into its zone.
    public init(tsb: Double) {
        self = Self.lowerBounds.last { tsb >= $0.lowerBound }?.zone ?? .injuryRisk
    }
}
