import SwiftUI
import HealthKit
import SwiftData
import CoreData
import TrainingCore
import TrainingHealthKit
import TrainingPersistence

/// A throwaway harness for exercising `TrainingHealthKit` and `TrainingPersistence` against real
/// HealthKit data and a real CloudKit-backed SwiftData store — the things `swift test` on its own
/// can never do, since there's no authorization, real health data, or CloudKit sync outside a
/// simulator/device running an actual app.
///
/// Section 4 saves imported activities through `TrainingPersistence`'s CloudKit-backed store;
/// `PersistenceHarness` (the macOS test app, same repo, same shared CloudKit container) reads them
/// back to confirm data actually crosses devices, not just round-trips locally.
struct ContentView: View {
    private let healthStore = HKHealthStore()

    @State private var authorizationStatus = "Not requested yet."
    @State private var snapshotText = ""
    @State private var importText = ""
    @State private var importedActivities: [Activity] = []
    @State private var persistenceStatus = ""
    @State private var store: SwiftDataStore?
    @State private var isBusy = false
    @State private var cloudKitEvents: [CloudKitEventLine] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Authorization") {
                    Text(authorizationStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Request HealthKit Authorization") {
                        Task { await requestAuthorization() }
                    }
                }

                Section("2. Athlete Snapshot") {
                    Button("Read Athlete Snapshot") {
                        Task { await readSnapshot() }
                    }
                    if !snapshotText.isEmpty {
                        Text(snapshotText)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }

                Section("3. Import Activities") {
                    Button("Import Activities (full history)") {
                        Task { await importActivities() }
                    }
                    if !importText.isEmpty {
                        Text(importText)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }

                Section("4. Save to Persistence Store (CloudKit)") {
                    Text(persistenceStatus.isEmpty ? "Import activities above first, then save them here — they'll sync to PersistenceHarness on the Mac via CloudKit." : persistenceStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Save \(importedActivities.count) Imported Activities") {
                        Task { await saveImportedActivities() }
                    }
                    .disabled(importedActivities.isEmpty)
                    Button("List What's Currently in the Store") {
                        Task { await listStoredActivities() }
                    }
                    Button("Delete ALL Activities From This Store", role: .destructive) {
                        Task { await deleteAllActivities() }
                    }
                }

                Section("5. CloudKit Sync Events") {
                    if cloudKitEvents.isEmpty {
                        Text("No CloudKit setup/import/export events observed yet. These fire independently of the buttons above — CloudKit exports in the background whenever there are local changes to push.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(cloudKitEvents) { event in
                            Text(event.text)
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("HealthKit Harness")
            .disabled(isBusy)
            .overlay {
                if isBusy {
                    ProgressView()
                }
            }
            .task {
                await openStore()
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
                    .receive(on: DispatchQueue.main)
            ) { note in
                recordCloudKitEvent(from: note)
            }
        }
    }

    private func recordCloudKitEvent(from note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }
        let type: String
        switch event.type {
        case .setup: type = "setup"
        case .import: type = "import"
        case .export: type = "export"
        @unknown default: type = "unknown"
        }
        let time = Date().formatted(date: .omitted, time: .standard)
        let line: String
        if event.endDate == nil {
            line = "[\(time)] \(type) started"
        } else if event.succeeded {
            line = "[\(time)] \(type) succeeded"
        } else {
            line = "[\(time)] \(type) FAILED: \(describeFully(event.error))"
        }
        cloudKitEvents.insert(CloudKitEventLine(text: line), at: 0)
        if cloudKitEvents.count > 25 {
            cloudKitEvents.removeLast()
        }
        // Also print to the console (NSLog rather than print so it's timestamped and shows up
        // even if Xcode's console is filtering stdout) -- the in-app Text can wrap oddly for a
        // long userInfo dump, and this is easy to copy/paste from the Xcode console in full.
        NSLog("[HealthKitHarness CloudKit] %@", line)
    }

    /// `CKError.localizedDescription` is often just "The operation couldn't be completed."; the
    /// actually-useful detail (retry-after hints, underlying network error, server message) lives
    /// in the NSError's userInfo, so dump that too rather than only the generic top-level message.
    private func describeFully(_ error: Error?) -> String {
        guard let error else { return "no error object" }
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription) userInfo=\(nsError.userInfo)"
    }

    private func openStore() async {
        do {
            let container = try makeHarnessModelContainer()
            store = SwiftDataStore(modelContainer: container)
        } catch {
            persistenceStatus = "Failed to open store: \(error.localizedDescription)"
        }
    }

    private func requestAuthorization() async {
        isBusy = true
        defer { isBusy = false }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = "HealthKit is not available on this device."
            return
        }
        do {
            try await HealthKitAuthorization.requestAuthorization(for: healthStore)
            authorizationStatus = "Authorization sheet completed. Check Settings > Health > Data Access & Devices to review or change what was granted."
        } catch {
            authorizationStatus = "Request failed: \(error.localizedDescription)"
        }
    }

    private func readSnapshot() async {
        isBusy = true
        defer { isBusy = false }

        let reader = HealthKitAthleteReader(healthStore: healthStore)
        let snapshot = await reader.snapshot(asOf: Date())
        snapshotText = """
        restingHeartRateBPM: \(snapshot.restingHeartRateBPM.map { String(format: "%.1f", $0) } ?? "nil")
        biologicalSex: \(snapshot.biologicalSex.map(String.init(describing:)) ?? "nil")
        estimatedMaxHeartRateBPM: \(snapshot.estimatedMaxHeartRateBPM.map { String(format: "%.1f", $0) } ?? "nil")
        """
    }

    private func importActivities() async {
        isBusy = true
        defer { isBusy = false }

        // Without passing `store` here, every re-import mints a fresh UUID for the same HealthKit
        // workout (Activity.id defaults to a new UUID when there's no existingID to reuse), so
        // upsert(_:) -- which matches by id -- can never recognize it as the same activity it
        // already has. Repeated Import+Save taps then silently pile up duplicate records instead
        // of updating the one that's already there. Passing `store` lets the importer look up the
        // existing id by source first.
        let importer = HealthKitActivityImporter(healthStore: healthStore, activityStore: store)
        do {
            let result = try await importer.importActivities(since: nil)
            importedActivities = result.upserted
            var lines = ["\(result.upserted.count) activities, \(result.deletedSources.count) deletions, anchor: \(result.anchor != nil ? "present" : "nil")", ""]
            for activity in result.upserted.prefix(25) {
                let sport = String(describing: activity.sport)
                let start = activity.start.formatted(date: .abbreviated, time: .shortened)
                lines.append("\(sport) — \(start) — \(Int(activity.duration))s — \(activity.heartRate.count) HR samples")
            }
            importText = lines.joined(separator: "\n")
        } catch {
            importedActivities = []
            importText = "Import failed: \(error.localizedDescription)"
        }
    }

    private func saveImportedActivities() async {
        isBusy = true
        defer { isBusy = false }

        guard let store else {
            persistenceStatus = "Store isn't open yet."
            return
        }
        do {
            try await store.upsert(importedActivities)
            persistenceStatus = "Saved \(importedActivities.count) activities to the store at \(Date().formatted(date: .omitted, time: .standard)). CloudKit sync happens in the background — check PersistenceHarness on the Mac after a few seconds."
        } catch {
            persistenceStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func listStoredActivities() async {
        isBusy = true
        defer { isBusy = false }

        guard let store else {
            persistenceStatus = "Store isn't open yet."
            return
        }
        do {
            let all = try await store.activities(in: .distantPast...Date.distantFuture)
            persistenceStatus = "\(all.count) activities currently in this device's store."
        } catch {
            persistenceStatus = "List failed: \(error.localizedDescription)"
        }
    }

    private func deleteAllActivities() async {
        isBusy = true
        defer { isBusy = false }

        guard let store else {
            persistenceStatus = "Store isn't open yet."
            return
        }
        do {
            let count = try await store.deleteAllActivities()
            persistenceStatus = "Deleted \(count) activities. CloudKit will propagate the deletions to other devices in the background."
        } catch {
            persistenceStatus = "Delete failed: \(error.localizedDescription)"
        }
    }
}

/// A single "CloudKit Sync Events" line, identified independently of its display text -- two
/// events can render to the identical string within the same clock second, and `ForEach` needs a
/// stable per-row identity distinct from that text to avoid "ID occurs multiple times" warnings.
private struct CloudKitEventLine: Identifiable {
    let id = UUID()
    let text: String
}

#Preview {
    ContentView()
}
