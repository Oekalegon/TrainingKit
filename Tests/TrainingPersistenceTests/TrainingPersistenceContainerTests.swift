import Foundation
import SwiftData
import Testing
@testable import TrainingPersistence

@Suite("TrainingPersistenceContainer")
struct TrainingPersistenceContainerTests {
    @Test("make(cloudKitDatabase: .none) builds a usable in-memory container")
    func makeLocalOnlyContainer() throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        _ = SwiftDataStore(modelContainer: container)
    }

    @Test("make(cloudKitDatabase: .automatic) doesn't throw even without an iCloud/CloudKit entitlement")
    func makeCloudKitContainerDoesNotThrowWithoutEntitlement() throws {
        // This test process has no iCloud/CloudKit capability configured, which is exactly the
        // scenario TrainingPersistenceContainer.make's doc comment describes: SwiftData doesn't
        // validate CloudKit connectivity synchronously at container-creation time, so `.automatic`
        // still succeeds here. A missing entitlement in a real app instead surfaces later, as a
        // silent/logged sync failure once SwiftData actually attempts to talk to CloudKit -- not
        // as a thrown error from this call. This test exists to keep that documented claim honest;
        // actual CloudKit sync itself needs a real device/entitlement and isn't exercised here.
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .automatic, isStoredInMemoryOnly: true)
        _ = SwiftDataStore(modelContainer: container)
    }
}
