import Foundation
import SwiftData

/// The persisted singleton row holding the fitness-metrics cache's dirty watermark.
///
/// One row per store, fetched-or-created exactly like ``AthleteProfileRecord`` — a single global
/// watermark value doesn't belong keyed into the per-day ``FitnessMetricsRecord`` rows.
@Model
public final class FitnessMetricsCacheStateRecord {
    /// `nil` means no explicit invalidation is pending.
    var dirtyWatermark: Date?

    init(dirtyWatermark: Date? = nil) {
        self.dirtyWatermark = dirtyWatermark
    }
}
