import Foundation
import SwiftData
@testable import TrainingPersistence

/// Creates `ModelContainer`s one at a time.
///
/// Swift Testing runs the suites in parallel, and each test makes its own container. Core Data
/// intermittently segfaults when several are created at once, inside
/// `-[NSSQLEntity_DerivedAttributesExtension _generateTriggerSQL]` (Apple's code, not ours), which
/// failed a whole test run at random. Creating them under one lock avoids it; the tests then use the
/// containers in parallel as before.
enum TestContainers {
    private static let lock = NSLock()

    /// `TrainingPersistenceContainer.make` under the lock.
    static func make(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .automatic,
        isStoredInMemoryOnly: Bool = false,
        storeDirectory: URL? = nil
    ) throws -> ModelContainer {
        lock.lock()
        defer { lock.unlock() }
        return try TrainingPersistenceContainer.make(
            cloudKitDatabase: cloudKitDatabase, isStoredInMemoryOnly: isStoredInMemoryOnly, storeDirectory: storeDirectory
        )
    }

    /// `ModelContainer(for:configurations:)` under the lock.
    static func modelContainer(for schema: Schema, configurations: [ModelConfiguration]) throws -> ModelContainer {
        lock.lock()
        defer { lock.unlock() }
        return try ModelContainer(for: schema, configurations: configurations)
    }
}
