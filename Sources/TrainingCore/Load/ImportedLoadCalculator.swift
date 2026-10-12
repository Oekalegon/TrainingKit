import Foundation

/// Scores an activity from the load a calendar export file gave it (MVP2-107): the figure the athlete's
/// other device worked out from its heart rate, for an activity whose heart-rate samples the file
/// doesn't carry.
///
/// Tried after heart-rate TRIMP (an activity with samples is scored from them) and before
/// ``DurationRPECalculator``. The method is ``LoadMethod/manual``: a load given to the app, not worked
/// out by it, so it isn't marked as an estimate.
public struct ImportedLoadCalculator: LoadCalculator {
    public init() {}

    public func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad {
        guard let value = activity.importedLoad, value.isFinite, value >= 0 else {
            throw LoadError.missingImportedLoad
        }
        return TrainingLoad(value: value, method: .manual, confidence: 1.0)
    }
}
