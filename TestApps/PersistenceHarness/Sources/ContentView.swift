import SwiftUI
import SwiftData
import CoreData
import TrainingCore
// `@testable` so this throwaway harness can call SwiftDataStore.deleteAllActivities(), which is
// deliberately internal (not part of any shipped app's public surface) -- see that method's doc
// comment in TrainingPersistence.
@testable import TrainingPersistence

/// A throwaway harness for confirming `TrainingPersistence`'s CloudKit sync actually crosses
/// devices: `HealthKitHarness` (the iOS test app, same repo, same shared CloudKit container) saves
/// activities imported from HealthKit; this Mac app reads them back to prove the sync path works
/// end to end, not just that both sides round-trip locally.
struct ContentView: View {
    @State private var store: SwiftDataStore?
    @State private var activities: [Activity] = []
    @State private var status = "Opening store…"
    @State private var isBusy = false
    @State private var autoRefresh = false
    @State private var cloudKitEvents: [CloudKitEventLine] = []

    private let autoRefreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Refresh") {
                        Task { await refresh() }
                    }
                    Toggle("Auto-refresh every 5s", isOn: $autoRefresh)
                    Spacer()
                    Button("Delete ALL Activities", role: .destructive) {
                        Task { await deleteAllActivities() }
                    }
                }

                List(activities.sorted { $0.start > $1.start }) { activity in
                    VStack(alignment: .leading) {
                        Text("\(String(describing: activity.sport)) — \(activity.start.formatted(date: .abbreviated, time: .shortened))")
                            .font(.headline)
                        Text("\(Int(activity.duration))s, \(activity.heartRate.count) HR samples, source: \(String(describing: activity.source))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 150)

                Text("CloudKit Sync Events")
                    .font(.headline)
                if cloudKitEvents.isEmpty {
                    Text("No CloudKit setup/import/export events observed yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    List(cloudKitEvents) { event in
                        Text(event.text)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    .frame(minHeight: 150)
                }
            }
            .padding()
            .navigationTitle("Persistence Harness (\(activities.count))")
            .disabled(isBusy)
            .task {
                await openStore()
                await refresh()
            }
            .onReceive(autoRefreshTimer) { _ in
                guard autoRefresh else { return }
                Task { await refresh() }
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
                    .receive(on: DispatchQueue.main)
            ) { note in
                recordCloudKitEvent(from: note)
            }
        }
        .frame(minWidth: 480, minHeight: 600)
    }

    private func openStore() async {
        do {
            let container = try makeHarnessModelContainer()
            store = SwiftDataStore(modelContainer: container)
            status = "Store open. Save some activities from HealthKitHarness on iOS, then Refresh."
        } catch {
            status = "Failed to open store: \(error.localizedDescription)"
        }
    }

    private func refresh() async {
        guard let store else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            activities = try await store.activities(in: .distantPast...Date.distantFuture)
            status = "Last refreshed \(Date().formatted(date: .omitted, time: .standard)) — \(activities.count) activities."
        } catch {
            status = "Refresh failed: \(error.localizedDescription)"
        }
    }

    private func deleteAllActivities() async {
        guard let store else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let count = try await store.deleteAllActivities()
            status = "Deleted \(count) activities. CloudKit will propagate the deletions to other devices in the background."
            activities = []
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
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
        NSLog("[PersistenceHarness CloudKit] %@", line)
        // A finished import means CloudKit delivered something -- refresh right away rather than
        // waiting for the next auto-refresh tick or a manual Refresh tap.
        if event.type == .import, event.endDate != nil, event.succeeded {
            Task { await refresh() }
        }
    }

    /// `CKError.localizedDescription` is often just "The operation couldn't be completed."; the
    /// actually-useful detail (retry-after hints, underlying network error, server message) lives
    /// in the NSError's userInfo, so dump that too rather than only the generic top-level message.
    private func describeFully(_ error: Error?) -> String {
        guard let error else { return "no error object" }
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription) userInfo=\(nsError.userInfo)"
    }
}

/// A single "CloudKit Sync Events" line, identified independently of its display text -- two
/// events can render to the identical string within the same clock second, and `List`/`ForEach`
/// need a stable per-row identity distinct from that text to avoid "ID occurs multiple times"
/// warnings.
private struct CloudKitEventLine: Identifiable {
    let id = UUID()
    let text: String
}

#Preview {
    ContentView()
}
