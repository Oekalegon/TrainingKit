import Foundation

/// A ``PaceModel`` and the date it takes effect, one entry of ``AthleteProfile/paceHistory``.
///
/// Kept dated, like ``HeartRateZoneSettings``, so a change of threshold pace is a record of when it
/// changed rather than an overwrite.
public struct PaceSettings: Sendable, Codable, Equatable {
    /// The first day this pace model applies.
    public var effectiveDate: Date
    /// The pace model in effect from ``effectiveDate``.
    public var paceModel: PaceModel

    /// Creates a dated pace model.
    ///
    /// - Parameters:
    ///   - effectiveDate: The first day the model applies.
    ///   - paceModel: The model in effect from then on.
    public init(effectiveDate: Date, paceModel: PaceModel) {
        self.effectiveDate = effectiveDate
        self.paceModel = paceModel
    }
}
