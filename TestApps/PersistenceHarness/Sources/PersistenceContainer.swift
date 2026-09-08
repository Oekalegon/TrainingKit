import SwiftData
import TrainingPersistence

/// The CloudKit container identifier shared with `HealthKitHarness` (the iOS test app) — both
/// apps must use this exact identifier, under the same Apple Developer Team, for activities saved
/// on iOS to sync here via CloudKit's private database.
///
/// Kept as a small standalone file (rather than importing anything from `HealthKitHarness`, which
/// isn't possible — they're separate app targets) so the two apps' copies are easy to spot and
/// keep in sync; if you change one, change the other.
///
/// Deliberately distinct from `TrainingApp`'s production container
/// (`iCloud.org.oekalegon.trainingkit.shared`) — never point this at that identifier. Both test
/// devices sign into the same real iCloud account this harness's setup requires, so sharing a
/// container would make this harness's data (and its destructive `deleteAllActivities()` test
/// helper) operate on the athlete's actual production training history.
let sharedCloudKitContainerIdentifier = "iCloud.org.oekalegon.trainingkit.testharness"

/// Builds the shared `ModelContainer` this harness reads activities from.
func makeHarnessModelContainer() throws -> ModelContainer {
    try TrainingPersistenceContainer.make(cloudKitDatabase: .private(sharedCloudKitContainerIdentifier))
}
