# Architecture Transition Document: Apple Health & iCloud Data Compliance

## 1. Executive Summary & Problem Statement
To expand the app's capability to global markets (including strict compliance with Norway's Forbrukertilsynet and EU/EEA regulations) and ensure seamless multi-device performance, the data storage architecture must be fundamentally updated. 

### The Problem
Apple App Store Review Guideline 5.1.3(ii) strictly states: *"Apps using the HealthKit framework that store users’ health information in iCloud will be rejected."* Apple enforces this broadly, covering not just raw biometrics, but also **processed or aggregated health data** (e.g., daily/weekly training loads, time in heart rate zones, fatigue scores, and physical aggregates). Storing these in a shared CloudKit container risks immediate app rejection. However, calculating these metrics on-the-fly from raw records every time the app launches introduces significant performance lag and severe battery drain.

### The Solution
Implement a **Dual-Database Split Architecture** using SwiftData (or CoreData). This separates non-health planning data (allowed in iCloud) from sensitive health metrics, caching the latter strictly on the local device sandbox.

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
