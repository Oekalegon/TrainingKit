# Test harnesses

Throwaway apps for exercising TrainingKit adapters against the real platform frameworks
`swift test` can never reach — real HealthKit authorization/data, and real CloudKit sync between
two actual devices. Not part of the library; nothing here ships.

- **HealthKitHarness** (iOS) — exercises `TrainingHealthKit`'s importer/athlete reader against
  real HealthKit data, then saves imported activities through `TrainingPersistence`'s
  CloudKit-backed store.
- **PersistenceHarness** (macOS) — reads that same CloudKit-backed store, to confirm activities
  saved on iOS actually sync across devices rather than just round-tripping locally.

## Opening the harnesses

Open **`TrainingKitHarnesses.xcworkspace`**, not either app's `.xcodeproj` directly. Both projects
depend on the local `TrainingKit` package (`path: ../../`), and Xcode refuses to load the same
local package from two separate project windows at once ("Couldn't load trainingkit because it is
already opened from another project or workspace") — the shared workspace resolves it once for
both.

To run both simultaneously (needed to test sync): pick the **PersistenceHarness** scheme with
destination "My Mac" and Run, then switch the scheme to **HealthKitHarness** with your iOS
device/simulator as destination and Run — they target different destinations, so both run
concurrently from the one workspace without conflict.

## CloudKit setup this requires

Both apps share one CloudKit container, `iCloud.org.oekalegon.trainingkit.shared` — set in both
`project.yml` files' entitlements *and* in each app's `Sources/PersistenceContainer.swift` (kept as
a small duplicated constant since the two are separate app targets that can't share a source file
directly; if you ever change one, change the other).

- **A paid Apple Developer Program membership is required.** Personal (free) Team IDs cannot use
  the iCloud/CloudKit capability at all — provisioning fails outright with "Personal development
  teams... do not support the Push Notifications and iCloud capabilities." Set `DEVELOPMENT_TEAM`
  in both `project.yml` files to a paid team's ID.
- Both devices/simulators must be **signed into the same iCloud account** as each other for
  activities to actually sync between them. That iCloud account has nothing to do with which
  Apple Developer Team signs the app — the dev team just owns/provisions the container; any
  iCloud user can sync their own private data through it.
- **Run via Xcode's own ▶ (or `xcodebuild`), not by launching the built `.app` directly** (e.g.
  `open` on the bundle, or executing the Mach-O directly). During initial testing, launching
  outside Xcode's normal path caused a spurious `CKErrorDomain error 6` ("Error connecting to
  CloudKit daemon") that never occurred when run normally.
- CloudKit Console (icloud.developer.apple.com/dashboard) only shows *your own* private database —
  i.e. whichever Apple ID you're signed into the console with. If your test devices use a
  different iCloud account than your developer account, Console will show an empty private
  database even while sync between your devices works fine. It's not a diagnostic for this setup.

## Regenerating the Xcode projects

Both projects are managed by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from their
`project.yml`. After editing a `project.yml`, regenerate its project:

```bash
cd TestApps/HealthKitHarness && xcodegen generate
cd TestApps/PersistenceHarness && xcodegen generate
```

The generated `.xcodeproj`s and `Generated/` plists are committed for convenience (so the
workspace opens and runs without requiring XcodeGen to be installed first) — regenerate and commit
the diff after any `project.yml` change.

## Re-importing without duplicating

`HealthKitHarness`'s importer is created with `activityStore: store`, so a re-import looks up each
workout's existing `Activity.id` by its HealthKit source before minting a new one — without that,
`HealthKitActivityImporter` has no way to know a workout was already imported, so every repeated
Import+Save produces a *second* record for the same workout (`SwiftDataStore.upsert(_:)` matches by
`id`, and a fresh id never matches anything already stored). If you ever see the Mac's activity
count balloon far past what's actually in Health, this is almost certainly why — check
`importActivities()` still passes `activityStore:` before looking anywhere else.

If duplicates have already piled up (from before this was wired up, or from any other cause), both
apps have a **"Delete ALL Activities"** button that clears the store and lets the CloudKit deletes
propagate to every other synced device — use it to reset to zero, then re-import cleanly.

## Debugging CloudKit sync

If sync stalls or fails, the in-app "CloudKit Sync Events" section (both apps) surfaces
`NSPersistentCloudKitContainer`'s setup/import/export events with full error detail (also mirrored
to the console via `NSLog`). For deeper diagnosis, flip either app's
`-com.apple.CoreData.CloudKitDebug 3` launch argument to `true` in `project.yml` (or toggle it live
in Xcode: Scheme > Edit Scheme > Run > Arguments) and regenerate — this unlocks Core Data's verbose
CloudKit mirroring logs, which is what actually surfaced the real "Error connecting to CloudKit
daemon" error underneath a generic, unhelpful `CKErrorDomain#6` during initial testing.
