# Architecture Transition Document: Apple Health & iCloud Data Compliance

## 1. Executive Summary & Problem Statement
To expand the app's capability to global markets (including strict compliance with Norway's Forbrukertilsynet and EU/EEA regulations) and ensure seamless multi-device performance, the data storage architecture must be fundamentally updated. 

### The Problem
Apple App Store Review Guideline 5.1.3(ii) strictly states: *"Apps using the HealthKit framework that store users’ health information in iCloud will be rejected."* Apple enforces this broadly, covering not just raw biometrics, but also **processed or aggregated health data** (e.g., daily/weekly training loads, time in heart rate zones, fatigue scores, and physical aggregates). Storing these in a shared CloudKit container risks immediate app rejection. However, calculating these metrics on-the-fly from raw records every time the app launches introduces significant performance lag and severe battery drain.

### The Solution
Implement a **Dual-Database Split Architecture** using SwiftData (or CoreData). This separates non-health planning data (allowed in iCloud) from sensitive health metrics, caching the latter strictly on the local device sandbox.

---

## Implementation status (MVP2-131)

Implemented in `TrainingPersistence` as **one `ModelContainer` with two `ModelConfiguration`s**, not two
containers, so `SwiftDataStore` and its single context still see everything while the data lands in two
store files (`TrainingPersistenceContainer.make(...)`):

| Store | File | CloudKit | Models |
|---|---|---|---|
| Synced ("default") | `default.store` | `.automatic` (the app's iCloud container) | `PlannedActivityRecord`, `StructuredWorkoutRecord`, `TrainingCycleRecord`, `RaceRecord`, `AthletePreferencesRecord` |
| Local ("Local") | `Local.store` | none | `ActivityRecord` (with its heart-rate samples), `DeletedActivitySourceRecord`, `ActivityJoinRecord`, `AthleteProfileRecord`, `FitnessMetricsRecord`, `FitnessMetricsCacheStateRecord` |

- **The athlete profile is split.** `AthleteProfileRecord` (local) holds the whole profile and the
  HealthKit import anchor. `AthletePreferencesRecord` (synced) holds only what the athlete types or
  chooses: name, picture, time zone, week start, main sport, the pace history and the HealthKit
  resting-heart-rate switch. Sex, date of birth and the heart-rate settings never sync.
  `SwiftDataStore.athleteProfile()` merges the two, the synced preferences winning, so a preference
  edited on another device shows up; `save(_:)` writes both. The import anchor is local because it is a
  per-device HealthKit anchor: a synced anchor would make a second device skip workouts it never
  imported.
- **Other devices import from their own Health**, as section 3 describes. A device without HealthKit
  data (a Mac without iCloud Health sync) therefore shows plans and preferences but no activities.
- **Migration.** The synced store keeps the old single store's file, so its CloudKit mirror carries on.
  On the first launch after the split, `LegacyStoreMigration` copies the activities, tombstones,
  joins and profile out of the old file (opened without CloudKit, and only read) into `Local.store`,
  then the split container drops the local-only tables from `default.store`. That deletes nothing in
  CloudKit: **records already in iCloud (activities, the old full profile) stay there** until the
  athlete deletes the app's iCloud data (Settings, Apple Account, iCloud, Manage Storage). Nothing
  automatic can remove them safely.
- **Known gaps:** a plan's `completedActivityID` syncs, but the activity it names exists only on the
  device that imported it, so on a second device a completed plan can read as matched to an activity
  that isn't there until the plan links are repaired (`TrainingModel.reconcilePlans(asOf:)`).

---

## 2. The Dual-Database Split Architecture

The app will run two distinct database containers locally. They operate independently to achieve zero backend cloud liability while keeping the interface completely responsive.

```
┌────────────────────────────────────────────────────────────────────────┐
│                              YOUR APP                                  │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
          ┌──────────────────────────┴──────────────────────────┐
          ▼                                                     ▼
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│       DATABASE 1: HYBRID        │           │     DATABASE 2: LOCAL ONLY      │
│     (SwiftData + CloudKit)      │           │          (SwiftData)            │
├─────────────────────────────────┤           ├─────────────────────────────────┤
│ • Training Calendars            │           │ • Weekly/Daily Training Loads   │
│ • Custom Workout Templates      │           │ • Time in Heart Rate Zones      │
│ • User Preferences / Settings   │           │ • Aggregated Fatigue Metrics    │
├─────────────────────────────────┤           ├─────────────────────────────────┤
│  🔄 Automatically Syncs to      │           │  🔒 Never Leaves the Device     │
│     iCloud across user devices  │           │     (Apple Review Compliant)    │
└─────────────────────────────────┘           └─────────────────────────────────┘
```

### Container 1: The Hybrid Store (Planning & Metadata)
* **Technology:** `SwiftData` with an active `CloudKit` container configuration.
* **Permitted Data Types:** Training plans, empty calendar blocks, user profile preferences, route configurations, coaching templates, and metadata typed manually by the user.
* **Behavior:** Automatically synchronizes text and dates across the user's personal devices via Apple's native iCloud backend. 

### Container 2: The Local-Only Store (Aggregated Health Cache)
* **Technology:** A separate `SwiftData` context explicitly configured *without* a CloudKit container identifier. 
* **Permitted Data Types:** Computed weekly mileage, time spent in anaerobic thresholds, chronic training load (CTL), and fatigue scores derived from raw workouts.
* **Behavior:** Acts as a high-speed local cache. It resides strictly inside the app’s local iOS sandbox. Data never travels to iCloud under your app's namespace, keeping the app 100% compliant with Apple Guideline 5.1.3(ii).

---

## 3. Data Flow & Cross-Device Synchronization

Because Container 2 does not sync to iCloud, cross-device synchronization relies on Apple's native, secure background pipelines:

1. **Activity Logged:** The user completes a workout. The raw workout data enters the local iOS **HealthKit** database.
2. **Apple Native Sync:** Apple automatically syncs the raw HealthKit database securely from the primary device (e.g., iPhone) to secondary devices (e.g., iPad) using its own end-to-end encrypted iCloud channels.
3. **App Launch on Secondary Device:** When the app opens on the iPad, it reads the newly arrived raw workouts from the local HealthKit database.
4. **On-Device Aggregate Compilation:** The app processes the math *once* on the secondary device, compiles the training load updates, and writes them to the iPad's **Local-Only Store (Container 2)**. 
5. **Instant UI Load:** For all subsequent app launches, the UI pulls directly from the local cache instantly (<2ms), protecting battery life.

---

## 4. Multi-User Architecture (Coach & Runner Sharing)

To scale the app into a collaborative platform allowing coaches to interact with runners, two distinct approaches must be strictly maintained to prevent privacy failures:

### Option A: Peer-to-Peer CloudKit Sharing (Continuous Sync)
* **Execution:** Utilize Apple’s native `UICloudSharingController` or `ShareLink`. 
* **Scope Limits:** You are permitted to share the custom zones containing data from **Container A (Planning Data)**. You cannot directly transmit raw HealthKit metrics through this zone.
* **UX Rule:** Consent must be requested via an explicit UI screen when first linking with a coach. A continuous background connection is permitted thereafter, provided a visible "Sharing Status" indicator and a non-negotiable **"Stop Sharing" kill switch** are present in the app settings to satisfy GDPR compliance.

### Option B: Local File Imports (On-Demand)
* **Execution:** Implement iOS's native `fileImporter` modifier in SwiftUI to accept athletic exchange file types (`.fit`, `.gpx`, `.csv`, `.json`).
* **Compliance Posture:** Highly secure. The runner explicitly exports a file from their device and provides it to the coach manually. The coach loads the document directly into the app. Parsing occurs entirely locally on the device, populating the coach's workspace without communicating with any remote servers.

---

## 5. Technical Implementation Blueprint

Developers must explicitly initialize separate model containers to prevent unintentional data leakage to CloudKit. Below is the structural SwiftUI setup:

```swift
import SwiftUI
import SwiftData

@main
struct WorkoutPlannerApp: App {
    // 1. Initialize the Hybrid Container (Syncs with CloudKit)
    var hybridContainer: ModelContainer = {
        let schema = Schema([TrainingPlan.self, UserPreferences.self])
        let config = ModelConfiguration(
            "HybridStorage",
            schema: schema,
            cloudKitDatabase: .private("com.yourcompany.workoutplanner.shared")
        )
        return try! ModelContainer(for: schema, configurations: [config])
    }()
    
    // 2. Initialize the Local-Only Container (Strictly Offline Cache)
    var localOnlyContainer: ModelContainer = {
        let schema = Schema([CalculatedTrainingLoad.self, HeartRateZoneCache.self])
        let config = ModelConfiguration(
            "LocalCacheStorage",
            schema: schema,
            cloudKitDatabase: .none // Explicitly disables iCloud/CloudKit syncing
        )
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Inject both containers into the environment
        .modelContainer(hybridContainer)
        .modelContainer(localOnlyContainer)
    }
}
```

---
*End of Specification Document.*
