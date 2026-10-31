import Foundation

/// The class of a race by its distance, for the paradigms whose session profiles differ per distance (MVP5-154):
/// ``TrainingParadigm/distanceProfiles``.
///
/// A race is put in the class whose distance it is nearest, the boundaries being 7.5 km, 15 km and 30 km:
/// up to 7.5 km is a ``fiveK``, up to 15 km a ``tenK`` and up to 30 km a ``halfMarathon``. A longer race has no
/// class: the marathon and the ultra keep the paradigm's own profiles.
public enum RaceDistanceClass: String, Sendable, Codable, Hashable, CaseIterable {
    /// Up to 7.5 km; the 5 km.
    case fiveK
    /// Above 7.5 km and up to 15 km; the 10 km.
    case tenK
    /// Above 15 km and up to 30 km; the half marathon.
    case halfMarathon

    /// The class of a race of `distanceMeters`, or `nil` for one above 30 km, below or at zero, or not finite.
    ///
    /// - Parameter distanceMeters: The race distance, in meters.
    public init?(distanceMeters: Double) {
        guard distanceMeters.isFinite, distanceMeters > 0 else { return nil }
        switch distanceMeters {
        case ...7_500: self = .fiveK
        case ...15_000: self = .tenK
        case ...30_000: self = .halfMarathon
        default: return nil
        }
    }
}
