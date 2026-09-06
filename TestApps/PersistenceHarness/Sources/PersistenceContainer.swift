import SwiftData
import TrainingPersistence

/// The CloudKit container identifier shared with `HealthKitHarness` (the iOS test app) — both
/// apps must use this exact identifier, under the same Apple Developer Team, for activities saved
/// on iOS to sync here via CloudKit's private database.
///
/// Kept as a small standalone file (rather than importing anything from `HealthKitHarness`, which
/// isn't possible — they're separate app targets) so the two apps' copies are easy to spot and
/// keep in sync; if you change one, change the other.
let sharedCloudKitContainerIdentifier = "iCloud.org.oekalegon.trainingkit.shared"

/// Builds the shared `ModelContainer` this harness reads activities from.
func makeHarnessModelContainer() throws -> ModelContainer {
    try TrainingPersistenceContainer.make(cloudKitDatabase: .private(sharedCloudKitContainerIdentifier))
}
