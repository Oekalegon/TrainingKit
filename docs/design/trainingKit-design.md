# trainingKit — Package Design (MVP 1)

Swift package for iOS 26+, watchOS 26+, macOS 26+. Library only, no UI.

Scope of MVP 1:
- Import completed activities (HealthKit first, file import later) and compute a training load (HR-TRIMP) per activity.
- Maintain a library of structured workouts, synced to Apple WorkoutKit where the platform allows.
- Let the user plan activities (structured workout + date) and estimate their expected load.
- Let the user lay out training cycles (macro / meso / micro, e.g. a 3:1 pattern with a recovery week) manually or from a template, and attach plans and statistics to them.
- Produce one continuous daily fitness series — measured in the past, projected in the future — with CTL / ATL / TSB / monotony / strain per day, plus period and cycle statistics.
- Evaluate the committed plan against injury-risk and progress guardrails (read-only in MVP 1; the generator that acts on the findings is MVP 2).

Designed so MVP 2 (plan generator), MVP 3 (LLM coach) and MVP 4 (calibration from planned-vs-actual residuals) slot in without reshaping the core.

---

## 1. Targets

Split so the pure model never imports an Apple platform framework. That keeps the math testable on any platform and keeps macOS (no WorkoutKit) and watchOS (limited HealthKit write, no persistence-heavy work) from constraining the core.

| Target | Depends on | Platforms | Purpose |
|---|---|---|---|
| `TrainingCore` | Foundation only | all | Models, load calculators, series engine, estimators, store protocols |
| `TrainingHealthKit` | Core, HealthKit | iOS, watchOS, macOS | Activity + HR sample import, resting HR, biological sex |
| `TrainingWorkoutKit` | Core, WorkoutKit | iOS, watchOS | Structured workout ↔ `CustomWorkout`, schedule sync |
| `TrainingPersistence` | Core, SwiftData | all | SwiftData models + CloudKit sync, conforms to Core store protocols |
| `TrainingTools` | Core | all | Provider-neutral tool registry, JSON schemas, `PlanSandbox` |
| `TrainingToolsAnthropic` | Tools | all | Messages API tool-use loop |
| `TrainingToolsFoundationModels` | Tools, FoundationModels | iOS, macOS | On-device model adapter |
| `TrainingFIT` (later) | Core | all | FIT/TCX import and FIT workout export for Garmin/COROS |

Test targets: `TrainingCoreTests` (bulk of the coverage), one small test target per adapter.

```swift
// Package.swift (sketch)
let package = Package(
    name: "trainingKit",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TrainingCore", targets: ["TrainingCore"]),
        .library(name: "TrainingHealthKit", targets: ["TrainingHealthKit"]),
        .library(name: "TrainingWorkoutKit", targets: ["TrainingWorkoutKit"]),
        .library(name: "TrainingPersistence", targets: ["TrainingPersistence"]),
        .library(name: "TrainingTools", targets: ["TrainingTools"]),
        .library(name: "TrainingToolsAnthropic", targets: ["TrainingToolsAnthropic"]),
    ],
    targets: [
        .target(name: "TrainingCore"),
        .target(name: "TrainingHealthKit", dependencies: ["TrainingCore"]),
        .target(name: "TrainingWorkoutKit", dependencies: ["TrainingCore"]),
        .target(name: "TrainingPersistence", dependencies: ["TrainingCore"]),
        .target(name: "TrainingTools", dependencies: ["TrainingCore"]),
        .target(name: "TrainingToolsAnthropic", dependencies: ["TrainingTools"]),
        .target(name: "TrainingToolsFoundationModels", dependencies: ["TrainingTools"]),
        .testTarget(name: "TrainingCoreTests", dependencies: ["TrainingCore"]),
    ]
)
```

Platform note: HealthKit is nominally available on macOS, but health data only appears there if the user has iCloud Health sync enabled, and WorkoutKit does not exist on macOS at all. Treat the Mac as a *viewer/planner* that receives data through `TrainingPersistence` + CloudKit rather than importing directly. Adapters are wrapped in `#if canImport(...)` and the Core store protocols are what the app talks to.

---

## 2. Core model (`TrainingCore`)

All model types are `Sendable` value types with stable `UUID` identifiers. `Double` throughout for anything numerical. One type per file.

### 2.1 Athlete

```swift
struct AthleteProfile: Sendable, Codable {
    let id: UUID                                    // stable identity; see "Multiple athletes" below
    var name: String                                // human-readable label, e.g. for a roster picker
    var sex: BiologicalSex                          // .male, .female, .unspecified (uses male coefficients)
    var paceHistory: [PaceSettings]                 // dated pace models (MVP2-132); `paceModel` is the
                                                       // latest, `paceModel(asOf:)` the one in effect then
    var paceModel: PaceModel                        // computed: used to turn distance steps into time
    var timeZone: TimeZone                          // daily bucketing boundary
    var weekStartsOn: Weekday                       // weekly stats boundary, default .monday
    var mainSport: Sport                            // primary sport, e.g. for a weekly overview
                                                       // highlighting one sport's duration/distance/
                                                       // TRIMP change above the rest; default .running
    var mainVenue: Venue?                           // where the athlete usually does mainSport; nil = none.
                                                       // Preselects a plan's venue (only for mainSport)
    var heartRateZoneHistory: [HeartRateZoneSettings] // resting/max HR + zone method, dated so
                                                       // recomputing an old activity's load uses the
                                                       // settings effective on its date, not today's
    var dateOfBirth: Date?                          // from HealthKit when known (MVP2-124); `age(asOf:)`
                                                       // counts whole years in the athlete's time zone
    var usesHealthKitRestingHeartRate: Bool         // MVP2-132: whether the host app merges HealthKit's
                                                       // resting HR into the history (default true)
    var avatarImageData: Data?                      // MVP2-132: the athlete's chosen picture, kept small
    var runAvailability: RunAvailability            // MVP5-104: free day slots per weekday (+ MVP5-127 per-slot options, MVP5-131 runs per weekday, MVP5-110 run types), one global setting
                                                       // (synced with the other preferences); default none
}
```

#### Editing the profile (MVP2-132)

`AthleteProfile+Editing` has the changes the athlete makes by hand, as pure functions applied through
`TrainingModel.updateAthlete(asOf:_:)`: `recordingHeartRateSettings(_:)` / `removingHeartRateSettings(on:)`
and `recordingPaceModel(_:from:)` / `removingPaceSettings(on:)`. Each entry takes effect from the start
of its day in the athlete's time zone, recording on a day that already has one replaces it, and the last
entry can't be removed. `paceHistory` mirrors `heartRateZoneHistory`: a profile stored with one
`paceModel` decodes it as an entry effective since the beginning of time, and the current pace model is
also written under its old key. Planning uses the latest entry (`paceModel`), like
`currentHeartRateZoneSettings`; `paceModel(asOf:)` gives the one in effect on a date. Changing the
time zone or week start rebuilds the whole fitness-metrics cache (`TrainingModel.athlete`'s `didSet`).

`HeartRateZoneModel` derives `deltaHRRatio(for bpm:)` from the profile and maps HR zones ↔ ratios so a workout step targeting "Zone 3" can be turned into a TRIMP intensity.

#### Max heart rate from workouts (MVP2-56)

Each `HeartRateZoneSettings` entry records where its max heart rate came from in
`maxHeartRateSource`:
- `.formula`: estimated from age (Tanaka); the default, and what older saved settings decode to;
- `.workout(activityID:)`: reached in an ordinary workout;
- `.fieldTest(activityID:)`: measured by the max HR field test (MVP2-154, below);
- `.labTest(measuredOn:)`: measured in a laboratory and entered by the athlete; the date is kept in the source because a later settings entry (a resting-HR update) copies the source forward and would make an old test look new;
- `.manual`: entered by the athlete (MVP2-132) without saying how it was found; an age formula never replaces it.

The sources are ranked by reliability (`reliabilityRank(asOf:)`): formula 0 < manual 1 < workout 2 < field test 3 < lab test 4 (LTHR: manual 0 < field test 1 < lab test 2). A lab test ages: after 2 years for max HR (it falls by roughly a beat a year) and 90 days for LTHR (it follows fitness) it ranks one step below a field test (max HR: with a workout, still above a formula or a typed-in figure; LTHR: with a typed-in figure). Both windows are our own choices. `isReplaceable(by:asOf:)` says whether a value from another source, dated `asOf`, may take a source's place *without the athlete deciding*, which is the guard for automatic updates: a host app's HealthKit merge must check `current.isReplaceable(by: .formula, asOf: today)` before writing an age estimate. The ranking doesn't stop a confirmed update: a workout peak above the recorded max proves the record too low whatever its source, and `FieldTestResult.replacesMoreReliableSource` (judged on the test's date) tells the app when a test would replace a fresh lab test, so it can warn or default to keeping it.

Max heart rate drives the Karvonen zones and the heart-rate-reserve ratio TRIMP is built on. An age
estimate is commonly about 10 bpm off for an individual, and the ratio isn't clamped above 1, so a
max set too low inflates every session's load and shifts every zone down.

The update is athlete-confirmed:
1. `PeakHeartRateDetector` finds the highest heart rate an activity *held*, guarding against
   three kinds of false highs:
   - **Short spikes** (strap static, poor contact): the peak is the highest value held for at
     least 10 s. For each sample take the minimum over the 10 s window starting there, then the
     largest of those minimums. A lone spike never raises a window's minimum.
   - **Cadence lock** (an optical sensor reporting running cadence as heart rate): a jump faster
     than 5 bpm/s, measured over at least 5 s on a 3-sample running median, followed later by an
     equally fast drop. The stretch between the two is discarded. The median keeps a lock's sharp
     edge but removes spikes and most noise; a real heart rises at about 1–3 bpm/s. A jump with
     no matching drop is kept rather than discarding the rest of the workout on a misfire, so a
     lock that lasts to the end of the recording can still reach the athlete.
   - **Stuck readings**: windows holding more than 230 bpm are skipped, and the best plausible
     window elsewhere still counts.

   Gaps over 15 s split the samples into separate runs, and invalid samples are dropped. Across
   500 seeds of simulated 3 bpm sensor noise on 1 km-style intervals, the detected peak stayed
   within 6 bpm of the true effort.
2. `TrainingModel.maxHeartRateSuggestion(among:)` returns the activity with the highest held peak
   above the *current* max. `scanForMaxHeartRateSuggestion(in:excluding:)` does the same over the store (skipping declined activities), for
   a one-time look back (about 12 months; max heart rate falls with age).
3. After the athlete confirms, `applyMaxHeartRate(_:asOf:)` calls
   `AthleteProfile.raisingMaxHeartRate(to:from:source:)`, saves the profile and recomputes, through
   `TrainingModel.updateAthlete(asOf:_:)` (below).

Raising is **raise-only** and **date-effective**:
- A workout below the max says nothing about the true maximum, so this flow never lowers it. A
  linked max-HR field test may (see Field tests below).
- The new value applies from the activity's start. Earlier entries keep their max, so past load is
  unchanged; that activity and everything after it are rescored. Later entries below the new value
  are raised too, so a later resting-HR update can't bring the old max back.

A host app that merges in fresh formula estimates (TrainingApp's HealthKit merge) must check
`current.maxHeartRateSource.isReplaceable(by: .formula, asOf: today)` before writing one, so an age
estimate never replaces a manual, workout, field-test or lab-test max (see the ranking above). Only a
lab test ages today; a field test's LTHR drifts too and doesn't yet. `MaxHeartRateSuggestion.replacesMoreReliableSource`
flags a workout peak that would replace a fresh lab-tested max, like the field test result's flag.

#### Field tests (MVP2-154)

A workout whose `purpose` is `.maxHRTest` or `.lthrTest` (MVP2-153) is a field test. When its activity
is linked to the plan, `TrainingModel.fieldTestResult(forActivity:)` measures it (`FieldTestMeasurer`):
- **Max HR test:** the highest heart rate *held* anywhere in the activity, by the same
  `PeakHeartRateDetector` as above, rounded to a whole bpm.
- **LTHR test (Friel):** the average heart rate over the last 20 minutes of the 30-minute effort; the
  first 10 are left out because the heart rate is still rising. The effort is the workout's longest
  timed step. Its window comes from the steps the Watch recorded (`ActivityStepAligner`); an
  activity not started from the scheduled workout falls back to the plan's own timing when its length is
  within 5% of the plan's total and the end of the window doesn't look like a cooldown (its last two minutes at least 90% of the window's average), and the result says so (`isEstimatedFromPlan`). Recorded steps that fit the plan but lack the effort mean the test wasn't done, so there is no fallback then. The tolerances (90% of the effort, 80% coverage, 5%) are our own choices, picked to refuse rather than mislead. The average is
  weighted by time, not by sample, and an interval longer than 15 s or with a value above 230 bpm
  counts as uncovered. A recorded effort under 90% of the planned length, or heart rate covering
  under 80% of the 20 minutes, is refused with a `FieldTestError` rather than guessed. A result at
  or below resting heart rate is refused too.

Like the max HR suggestion, the result is offered and applied only when the athlete confirms
(`applyFieldTestResult(_:asOf:)`, through `updateAthlete`; a no-op if the activity has since been deleted or unlinked from a test of that kind). Unlike it, a test result may **lower** the
max, because a test is a deliberate attempt at the maximum; an ordinary workout still only raises it.
It is date-effective from the test activity's start
(`AthleteProfile.settingMaxHeartRate(to:from:source:)`,
`settingLactateThresholdHeartRate(to:from:source:)`). The settings in effect on that date are the
baseline; later entries that still carry the baseline's value and source (a resting-HR update copies
them) follow, and a later entry with a different value or source is a later measurement and is kept.
`HeartRateZoneSettings.lactateThresholdSource` (`.manual`, the default and what older data decodes
to, `.fieldTest(activityID:)` or `.labTest(measuredOn:)`) records how the LTHR was obtained.

An activity can show up in both flows: its peak may beat the max, so `maxHeartRateSuggestion` would also
offer it as a raise. A host app should ask `fieldTestResult` first and not offer the raise for an
activity that is a test.

#### Updating the athlete (MVP2-101)

Every change to `TrainingModel.athlete` goes through `updateAthlete(asOf:_:)`. It takes a
`(AthleteProfile) -> AthleteProfile` transform and runs it in the same queue as imports, then saves,
assigns and recomputes. Reading `athlete`, saving and assigning separately leaves a gap across the
save's `await`: two updates started together both start from the same old profile, so the model
keeps whichever assigns last and the store keeps whichever saves last. A max-HR update and a
HealthKit resting-HR refresh racing like this used to lose the raised max. With the queue, each
transform sees the profile the update before it left, so both changes survive.

#### Multiple athletes

Every store protocol, `TrainingModel`, `PlanSandbox`, and tool context already assume "one instance
= one athlete" — that's already sufficient for a coach-style host app to support a roster: construct
one `StoreSet` (backed by its own `ModelContainer`/CloudKit database — exactly the one container a
single-athlete app already uses, just one per athlete instead of one total) and one `TrainingModel`
per athlete, keyed by `AthleteProfile.id`. No store-protocol method gains an athlete parameter and no
persisted record gains an `athleteID` column — isolation comes from using separate store instances,
not from filtering shared rows within one. `TrainingHealthKit`/`TrainingWorkoutKit` stay single-
device/single-athlete regardless (Apple's own APIs have no notion of a second athlete's data on the
same device); a true "coach sees a remote athlete's live data" flow — most plausibly via CloudKit
sharing, granting the coach's iCloud account read/plan-write access to an athlete's private
database — is unscoped future work with no design here yet.

### 2.2 Completed activities

```swift
struct Activity: Identifiable, Sendable, Codable {
    let id: UUID
    var source: ActivitySource        // .healthKit(uuid), .fitFile(url), .manual, .testing
    var sport: Sport
    var venue: Venue?                 // where it happened, if known; see Venue below
    var isSportEdited: Bool           // athlete chose sport/venue (TrainingModel.setSport); re-imports and
                                       // join rebuilds then keep them. Call refreshPaceHistory afterwards.
                                       // Unedited, a linked activity takes its plan's sport and venue
                                       // (workout venue, else athlete default, else recorded), on auto-match,
                                       // manual link, re-import and join rebuild; unlinking leaves them
    var start: Date
    var duration: TimeInterval
    var distanceMeters: Double?
    var heartRate: [HeartRateSample]  // may be empty
    var linkedPlanID: UUID?           // reconciliation with a PlannedActivity
    var scheduledPlanID: UUID?        // the plan the Watch workout was started from (hint; MVP2-120)
    var steps: [ActivityStep]         // the steps the Watch recorded for a plan-started workout (MVP2-146)
}

struct HeartRateSample: Sendable, Codable {
    let time: Date
    let bpm: Double
}
```

HR samples are kept on the activity (not just the resulting load) so a recalculation with a changed HRmax or a changed calculator is possible without re-importing.

### 2.3 Training load

```swift
struct TrainingLoad: Sendable, Codable {
    var value: Double                 // TRIMP units
    var method: LoadMethod            // .exponentialTRIMP, .estimatedFromPlan, ...
    var confidence: Double            // 1.0 measured, < 1 for estimates; used by MVP 4
}

protocol LoadCalculator: Sendable {
    func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad
}
```

`ExponentialTRIMPCalculator` is the MVP implementation:

- Integrates Banister's exponential TRIMP over the HR stream, trapezoidally between consecutive samples.
- Coefficients `(0.64, 1.92)` male, `(0.86, 1.67)` female, held in a `TRIMPCoefficients` value so MVP 4 can tune them.
- Gaps > 60 s between samples are not integrated (treated as a pause), configurable.
- Throws `LoadError.noHeartRateData` rather than returning 0, so callers can fall back to `DurationRPECalculator` (duration × RPE) for activities without HR.

### 2.4 Structured workouts (the library)

```swift
struct StructuredWorkout: Identifiable, Sendable, Codable {
    let id: UUID
    var name: String
    var sport: Sport
    var venue: Venue?                 // mapped to CustomWorkout.location, so the Watch doesn't ask
                                       // "Indoor or Outdoor?"; nil = unspecified (the Watch asks)
    var sessionType: SessionType?     // e.g. .long, .interval, .hillRepeats; nil = unclassified.
                                       // Used by PlanGenerator (§8.1) to match day preferences —
                                       // doesn't affect load calculation or WorkoutKit/FIT export.
    var blocks: [WorkoutBlock]
    var workoutKitID: UUID?           // identity of the synced WorkoutKit plan, nil if unsynced
    var purpose: WorkoutPurpose       // .general, .maxHRTest or .lthrTest (MVP2-153); copied from the
                                       // template on instantiate; old data decodes as .general. Doesn't
                                       // affect load; marks a field test whose result is read from the
                                       // activity linked to its plan (MVP2-154)
}

// The built-in field tests (MVP2-153): the max HR test (our own protocol, not a published one) is a warmup, three 3-minute RPE 9 efforts with
// 1-minute recoveries and a 3-minute all-out effort (result: highest heart rate held); Friel's LTHR test
// (TrainingPeaks, "Joe Friel's Quick Guide to Setting Zones") is a warmup and one 30-minute RPE 9 effort
// (result: average heart rate over its last 20 minutes). A workout's purpose is fixed when it is instantiated. Both
// target RPE, not heart-rate zones, since the zones are what they set; WorkoutKit can't send RPE alerts,
// so the Watch just shows the steps' times.

// Deliberately a small set of broad categories, used to match day preferences (§8.1).
// Template specifics (fartlek, fast finish, the interval variants) belong to the
// StructuredWorkout, not to a new case.
enum SessionType: String, Sendable, Codable {
    case easy, long, interval, tempo, hillRepeats, recovery, race
}

// Sport says what is done; Venue says where, and is separate so every sport doesn't need an
// indoor/outdoor/trail/track case (MVP2-151). Stats group by Sport alone, so all runs count as running.
// A nil venue is compatible with any venue; two venues must agree on indoor vs outdoor (surfaces
// don't count) for activities to be "the same kind" (joins, overlaps, plan matching, pace history).
// WorkoutKit only carries indoor/outdoor (CustomWorkout.location), so the surface is dropped there.
// A WorkoutTemplate.venue is a constraint: nil lets the plan choose, .outdoor(nil) allows only outdoor
// surfaces, and a venue with a surface fixes it. Data written before Venue (Sport cases indoorRunning /
// outdoorRunning) decodes as .running plus .indoor(nil) / .outdoor(nil).
enum Venue: Sendable, Codable, Hashable {
    case indoor(IndoorSurface?)       // .treadmill, .track
    case outdoor(OutdoorSurface?)     // .track, .road, .trail, .offtrail
}

struct WorkoutBlock: Sendable, Codable {
    var steps: [WorkoutStep]
    var repetitions: Int              // 1 for warmup/cooldown, N for interval sets
}

struct WorkoutStep: Sendable, Codable {
    var kind: StepKind                // .warmup, .work, .recovery, .cooldown
    var goal: StepGoal                // .time(seconds) | .distance(meters) | .open
    var target: IntensityTarget?      // .heartRateZone(Int) | .heartRateRange(lo, hi) | .pace(range) | .power(range) | .rpe(Int)
}
```

This is deliberately a superset-neutral shape: every `StepGoal`/`IntensityTarget` here maps 1:1 onto WorkoutKit's `WorkoutStep`/`WorkoutGoal`/`WorkoutAlert`, and onto FIT workout steps, without either adapter needing extra fields. `.open` steps are estimated with a default duration from the athlete profile when no time/distance is given.

### 2.5 Planned activities

```swift
struct PlannedActivity: Identifiable, Sendable, Codable {
    let id: UUID
    var workoutID: UUID
    var date: Date                    // calendar day in athlete's timezone
    var expectedLoadOverride: Double? // manual override of the estimator
    var completedActivityID: UUID?    // set on reconciliation
    var cycleID: UUID?                // the micro this plan belongs to; derived from date if nil
    var planID: UUID?                 // the TrainingPlan it belongs to (MVP5-124)
}
```

A planned activity is just workout + date; everything else is derived. Keeping it minimal is what lets MVP 2 generate plans as plain data.

#### Training plans (MVP5-124)

A `TrainingPlan` (`id`, `name`, `status` of `.draft`/`.active`/`.archived`, `macroCycleID`, `targetRaceID`, `createdDate`) groups the `PlannedActivity` values and `TrainingCycle`s that belong together through their `planID`, so several plans can exist side by side with **at most one active** (`draft`, `active`, `archived`, or `cancelled` with a `cancelledDate`; if a sync leaves several active, the oldest by `createdDate` is the one in use on every device). Only the active plan's workouts and cycles are in `TrainingModel.plans`/`.cycles`, and so in the fitness series, statistics, activity matching, pace history, calendar export and the `PlanSandbox` snapshot; a draft, archived or cancelled plan stays in the store, editable and previewable (`TrainingModel.plannedActivities(ofPlan:in:)`, `cycles(ofPlan:in:)`). Planned workouts that an activity completed stay in `plans` whatever their plan's status, so a replaced plan's history stays visible and every activity's `linkedPlanID` still resolves. Workouts and cycles with no plan count as part of the active plan (the filter excludes *inactive* plans rather than selecting the active one), so data written before plans existed, or by another device on an older version, never drops out of the series.

Stored in an optional `TrainingPlanStore` (`StoreSet.trainingPlanStore`; `nil` means no plans and everything counts), with a synced `TrainingPlanRecord` in the CloudKit store. Two multi-record guarantees live in the store: `upsertTrainingPlan(_:cancelingActivePlanOn:)` ends any other active plan (draft, or cancelled with a date) in the same write, and `deleteTrainingPlan(id:)` removes the plan, its cycles and its planned workouts in one save, **except that a plan with at least one completed planned workout is history and is never deleted** (`TrainingPlanError.hasCompletedWorkouts`; `TrainingModel.trainingPlanHasCompletedWorkouts(id:)` lets a caller check first and offer to archive instead), so an activity's link to its planned workout and that workout's link to its plan always stay intact. Sibling cycles only have to avoid overlapping *within the same plan* (`CycleNestingValidator`), so two plans can lay out the same weeks differently.

`TrainingModel` adds `createTrainingPlan(named:status:targetRaceID:)`, `save(_:)`, `activateTrainingPlan(id:)`, `setStatus(_:ofTrainingPlan:)`, `renameTrainingPlan(id:to:)`, `duplicateTrainingPlan(id:named:)` (a draft copy with the cycles, parents remapped, and the uncompleted workouts from today on) and `deleteTrainingPlan(id:)` (refused for a plan with a completed workout), each reloading and recomputing. A workout or cycle added without a plan goes into the active plan; if there is none, "My plan" is created and activated. `load(in:)` moves everything that has no plan into the active plan once per model, creating "Current plan" (a fixed id, so two devices converge on one row) first if needed, which migrates data written before plans existed. It is `TrainingPlanStore.adoptUnassigned(intoActivePlanOrNew:)`, one fetch-and-save inside the store, so it can't overwrite a link an import writes at the same moment; best effort, logged on failure. `duplicateTrainingPlan` is one `insertTrainingPlan(_:cycles:plannedActivities:)` write. Activating a plan ends the previous one: if it has a completed workout (the athlete followed it) it is **cancelled** and dated that day (`TrainingModel.cancelTrainingPlan(id:)` does the same explicitly), otherwise it becomes a draft; archiving or cancelling the active plan leaves none active. Past workouts, their links to planned workouts and those workouts' links to their plans are never deleted: besides plans, `TrainingModel.deletePlan(id:)` and `PlanSandbox.commit` refuse to delete a planned workout an activity completed (`TrainingPlanError.workoutIsCompleted`; unlink the activity first if the match was wrong). Plans don't affect the persisted fitness-metrics cache, which only holds past days: switching the active plan just recomputes the projection.

#### Default titles (MVP2-110)

`WorkoutTemplate.defaultTitle(values:distanceSystem:)` names a planned workout from its parameters: "50min Easy Run", "23 km Long Run", "10x8sec Hill Sprints". It reads the instantiated workout's structure rather than a per-template rule, so a new template needs no changes: a block repeated more than once is an interval set ("reps x first work step"), otherwise the longest `.work` distance if there is one (warmup and cooldown are timed and can't be added to a distance), otherwise the total time of every timed step, warmup and cooldown included, so a 30-minute easy run between two 5-minute steps is "40min Easy Run". Open-ended steps add nothing (their length is unknown; an interval set is named by its repetitions and effort anyway). The name is `titleName` when set (a shorter name, e.g. "Hill Sprints"), otherwise `name` with each word capitalized. Durations are written "8sec", "90sec", "2min", "1h30min"; distances as "400 m" / "23 km", or "440 yd" / "13.1 mi" for `DistanceSystem.imperial`. A workout with no usable work goal (open-ended, or a non-positive or non-finite value) is titled with the name alone. The strings are English and not localized.

### 2.6 Expected load estimation

```swift
protocol PlannedLoadEstimator: Sendable {
    func estimatedLoad(for workout: StructuredWorkout, athlete: AthleteProfile) -> TrainingLoad
}
```

`TRIMPPlanEstimator` walks the steps: each step's duration comes from its goal (`.time` direct, `.distance` via `PaceModel` at the step's target intensity, `.open` via default), each step's intensity comes from `IntensityTarget` → `deltaHRRatio` (zone midpoint), and the same Banister formula is applied per step. Result is a `TrainingLoad` with `method: .estimatedFromPlan` and `confidence < 1`. MVP 4 replaces this with a calibrated estimator that scales by observed residuals; the protocol boundary is the seam.

`LinkedActivityRefinedEstimator` wraps any estimator and refines it from completed plans: the estimate of a workout is the base estimate times the **recency-weighted median** of `actual TRIMP ÷ base estimate of the workout that was done`, over completed plans of the same library workout or the same template (`templateID`). Comparing estimates rather than raw TRIMP scales the figure to the template's parameters and to the zones its steps target; a run with the same parameters simply gives its actual TRIMP. A run's weight halves for every 60 days it is older than the newest matching run (relative to the newest, so nothing reads `.now`). A run whose duration is outside 0.75–1.33× the workout's estimated duration (a session cut short, a join) is skipped, and confidence rises with each reference (0.7 → 0.85 → 0.925, capped at 0.95). A plan's own activity is among the references, so its estimate is its own load; use `excludingReferences(onOrAfter:)` to estimate it as it was before, which anything computing expected-versus-actual residuals must do. `TrainingModel.refinedEstimator()` builds it from every completed plan in the stores and feeds the fitness series, calendar export (metrics and entries) and calendar import; an app's own `StatisticsCalculator` should be given the same estimator to show matching figures. A plan's `expectedLoadOverride` still wins. `TrainingModel` wraps its estimator with it for the load series and the calendar export, and exposes it as `TrainingModel.refinedEstimator()` (async; built once from the plan history and kept until the next `recompute` that follows a change, which every mutation goes through, so a host app's call right after an import shares the build `recompute` just made; an import that upserted or deleted nothing keeps it (an unchanged re-import still rebuilds), so a no-op pull-to-refresh doesn't rebuild it, while an import that fails part-way always drops it, and edits made to the stores behind the model's back (iCloud sync) are seen at the next change that does go through it; MVP2-161; `loadRefinedEstimator()` is the throwing variant that reports an unreadable store instead of returning the base estimator; MVP2-160. A build reads every plan and each completed activity and scores them: about 0.4 s for 400 one-hour runs on an in-memory SwiftData store in a debug build, growing linearly with the history) so a host app's own planned-load figures agree with them.

---

## 3. The fitness series engine

### 3.1 Daily bucketing

`DailyLoadSeries` owns the merge of actual and planned loads into one `[DayLoad]`, one entry per calendar day in `AthleteProfile.timeZone`, with no gaps (days with nothing are `0`). The merge rule per day:

| Day is | Rule |
|---|---|
| Before today | Sum of actual loads. Planned-but-not-done contributes 0 (it's history now). |
| Today | Actual loads if any exist, otherwise the planned estimate. |
| After today | Sum of estimated loads for planned activities. |

"Today" is an injected `Date` (not `Date()`) so the series is deterministic in tests and so the planner can ask "what does the curve look like as of next Monday".

```swift
struct DayLoad: Sendable {
    let day: Date               // start of day
    let load: Double
    let isProjected: Bool       // any part of it came from an estimate
}
```

### 3.2 Metrics

```swift
struct FitnessMetrics: Sendable {
    let day: Date
    let load: Double
    let ctl: Double             // 42-day EWMA
    let atl: Double             // 7-day EWMA
    let tsb: Double             // yesterday's CTL − yesterday's ATL
    let monotony: Double        // mean / stdev of the trailing 7 days
    let strain: Double          // trailing 7-day sum × monotony
    let isProjected: Bool
}

struct LoadModelParameters: Sendable, Codable {
    var ctlTimeConstantDays: Double = 42
    var atlTimeConstantDays: Double = 7
    var monotonyWindowDays: Int = 7
}

struct FitnessMetricsCalculator: Sendable {
    func metrics(for series: [DayLoad], parameters: LoadModelParameters,
                 seed: (ctl: Double, atl: Double)?) -> [FitnessMetrics]
}
```

Notes:
- EWMA form: `ctl[d] = ctl[d-1] + (load[d] − ctl[d-1]) / τ`. Sequential by nature; no Accelerate/Metal needed here. Monotony's rolling mean/stdev is the only thing worth vectorising and even that is a few thousand elements at most.
- Monotony is undefined when stdev is 0 (a week of identical loads, or a week of rest). Return `.nan` and let the UI decide, don't clamp — a rest week isn't "monotonous".
- `seed` lets a user who imports only recent history start from a known CTL/ATL instead of ramping from zero. Without a seed the first ~42 days of CTL are unreliable and `FitnessMetrics` should surface that (an `isWarmingUp` flag is reasonable).

### 3.3 Observable facade

```swift
@Observable
@MainActor
final class TrainingModel {
    private(set) var metrics: [FitnessMetrics] = []
    private(set) var activities: [Activity] = []
    private(set) var plans: [PlannedActivity] = []
    private(set) var workouts: [StructuredWorkout] = []
    private(set) var cycles: [TrainingCycle] = []
    private(set) var cycleStats: [CycleStats] = []
    private(set) var evaluation: PlanEvaluation?
    var athlete: AthleteProfile
    var parameters: LoadModelParameters

    func add(_ plan: PlannedActivity) async throws
    func add(_ cycles: [TrainingCycle]) async throws          // e.g. output of CycleLayoutBuilder
    func importActivities(from source: ActivityImporting) async throws
    func recompute(asOf today: Date = .now) async
}
```

The recompute runs off the main actor (a `nonisolated` helper or a dedicated `actor SeriesBuilder`) and publishes the result back. It's cheap enough that a full recompute on any change is fine for MVP; incremental recompute from the changed day forward is an easy later optimisation because the EWMA only depends on the prior day.

Logging: `os.Logger` with subsystem `com.<you>.trainingKit`, categories `Import`, `Load`, `Series`, `WorkoutKit`.

---

## 4. Store protocols

Core defines the storage contract; `TrainingPersistence` implements it with SwiftData in two stores (MVP2-131): plans, workouts, cycles, races, goals and the athlete's own preferences sync through CloudKit; activities (with their heart-rate samples), joins, tombstones, the fitness-metrics cache and the HealthKit-derived parts of the profile stay on the device, because Apple's guideline 5.1.3(ii) forbids storing health information in iCloud. Each device imports its own activities from HealthKit. See `docs/design/icloud-healthkit-compliance-architecture.md` for which model lives where and how an old single store is migrated.

A `Goal` (MVP2-139) is a non-event target with no date and no calendar presence, separate from `Race`: its `GoalTarget` is a time over a distance ("sub-20 5k"), a volume per week, month or year for a sport or all sports ("run 1500 km this year"), or free text. `GoalStore.goals()` has no range because a goal has no date, and `TrainingModel.goals` loads with the rest. Nothing reads goals yet; a management UI and plans that use them are MVP 5. `SwiftDataStore.goals()` skips and logs a record it can't decode, so a target kind written by a newer version on another device doesn't fail the whole load.

The athlete's own `WorkoutTemplate`s (MVP2-140) are stored the same way: `WorkoutTemplateStore` (`templates()`, `template(id:)`, `upsert(_:)`, `deleteTemplate(id:)`), an optional `StoreSet.templateStore`, a synced `WorkoutTemplateRecord`, and `TrainingModel.templates` with `add(_:)` and `deleteTemplate(id:)`. Only custom templates are stored; the built-in ones stay in `BuiltInWorkoutTemplates`. Deleting or editing a template never touches plans already made from it, since each plan instantiated its own `StructuredWorkout`. `SwiftDataStore.templates()` skips and logs a record it can't decode, as for goals. Deleting a template that a plan's workout was made from archives it instead (MVP2-142: `WorkoutTemplate.archivedDate`, `TrainingModel.deleteTemplate(id:asOf:)` returning `TemplateRemoval`), so those plans keep their template for editing parameters and for exports; every plan counts, past or upcoming, and a template no plan uses is removed. `TrainingModel.templates` includes archived templates, so a caller offering templates filters on `isArchived`.

```swift
protocol ActivityStore: Sendable {
    func activities(in range: ClosedRange<Date>) async throws -> [Activity]
    func activityListItems(in range: ClosedRange<Date>) async throws -> [ActivityListItem]   // MVP2-129
    func upsert(_ activities: [Activity]) async throws
    func activity(sourceID: String) async throws -> Activity?   // dedupe on re-import

    // Joined activities (MVP1-80): one session accidentally recorded in pieces.
    func saveJoin(_ merged: Activity, components: [UUID], replacing: [UUID]) async throws
    func components(ofJoinedActivity id: UUID) async throws -> [Activity]
    func joinedActivity(containing componentID: UUID) async throws -> Activity?
    func unjoinActivity(id: UUID) async throws
}

protocol PlanStore: Sendable { ... }
protocol WorkoutLibraryStore: Sendable { ... }
protocol CycleStore: Sendable { ... }       // enforces nesting/overlap rules on insert
protocol AthleteStore: Sendable { ... }
```

An `InMemoryStore` implementing all five ships in Core for tests and previews.

**Joined activities.** When the overlap checker recommends `.join` (same sport family, pieces within `joinGapTolerance` of each other), `TrainingModel.joinActivities` stores a combined `Activity` plus a link to its pieces (`saveJoin`, atomic). Nothing is deleted:

- The pieces keep their own `source`, so a re-import updates them in place and never resurrects them as separate activities.
- `activities(in:)` **hides the pieces and returns the join** (a range that reaches only a later piece still returns the join), so the fitness recompute, overlap checks and the UI see one activity.
- The link lives in its own table so a re-import rewriting a piece's record can't clear it.
- `unjoinActivity` reverses a join. Deleting a join deletes its pieces (tombstoned) except any piece another join still uses.
- A piece deleted at its origin dissolves the join; a re-import that changes a piece rebuilds the join in place, keeping its own plan link and perceived exertion.
- A component can belong to one join at a time (`ActivityJoinError.componentAlreadyJoined`); joining a joined activity flattens into one join of N.

**List items (MVP2-129).** `activityListItems(in:)` returns what `activities(in:)` shows, joins included, as `ActivityListItem`s (id, sport, start, duration, distance, linked plan) without the samples. The protocol default maps `activities(in:)`; `SwiftDataStore` overrides it to decode only those fields from each payload, so a list over years of history never builds heart-rate or speed samples. The order is unspecified.

The join operations are part of `ActivityStore` (rather than a separate protocol) because the hiding has to happen inside `activities(in:)`; this costs every conformer three extra methods. Revisit if a second conformer family appears.

---

## 5. Adapters

### 5.1 `TrainingHealthKit`

```swift
protocol ActivityImporting: Sendable {
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult
}
```

`HealthKitActivityImporter`:
- `HKAnchoredObjectQuery` on `HKWorkoutType` → new/updated/deleted workouts since the last anchor. Anchor persisted via `AthleteStore`.
- For each workout, a scoped `HKSampleQuery` on `heartRate` bounded to the workout's `startDate...endDate`, sorted, mapped to `[HeartRateSample]`.
- `Activity.source = .healthKit(workout.uuid)`; the UUID is the dedupe key.
- **Speed (MVP2-146):** a second scoped query reads the workout's running speed (cycling speed for a ride; none for sports that record neither), unpacking series like heart rate, and keeps it averaged over 5-second windows (`[SpeedSample].downsampled(everySeconds:)`) in `Activity.speed`: an hour is about 700 samples, not thousands, and a pause stays a gap. Speed is what the pace chart and `PaceHistory` (and with it the pace forecasts) read; before this the importer stored none, so `PaceHistory` was empty on a real device. An activity imported earlier has no speed until it is re-imported (Force Full Resync), and none until the athlete allows the speed types. A failed query is logged and the workout still imports, and a re-import that comes back with no speed (or no heart rate) keeps the stored one rather than replacing it with nothing. Each workout now makes about twice the HealthKit queries, so a full resync of a long history takes longer; not yet measured.
- **Steps (MVP2-146):** a workout started from a scheduled plan is saved with one `HKWorkoutActivity` per step (a repeat is one per repetition and step), each ending where the next begins. The importer turns every workout activity whose metadata has `WOIntervalStepKeyPath` into an `ActivityStep` (`Activity.steps`): the key path `block.repetition.step` (all from 0; block 0 is the warm-up, the plan's blocks follow, the cool-down is last), exact start and end, the active duration, and from the activity's own statistics its distance (`distance…` types) and average heart rate, plus `HKElevationAscended` and `WOIntervalStepSuccessful` from the metadata. Pace is duration over distance. The `HKWorkoutEvent` segments are not steps (they are kilometre and mile splits across the whole workout) and are ignored. Seen on a real long run and a hill-sprint workout; a plan with no warm-up has not been seen, so `ActivityStepAligner` accepts either numbering, and refuses to align when a partial recording fits both differently. The active duration is HealthKit's `HKWorkoutActivity.duration`; no step inspected so far contained a pause, so it has only been seen equal to `end - start`. To check what the Watch recorded for a workout, use the app's Developer ▸ Inspect Recent Workouts (it prints each step's key path, metadata and statistics). Two limits: distance is only readable once the athlete has allowed the distance types (`HealthKitAuthorization.readTypes`), and an activity imported before this field has no steps until it is re-imported (Force Full Resync).
- `HealthKitAthleteReader` supplies resting HR (median `restingHeartRate` sample over the trailing 1–2 weeks, via `RestingHeartRateSmoother`, to absorb day-to-day noise before it feeds zone settings) and `biologicalSex()` to pre-fill `AthleteProfile`; the snapshot also carries `dateOfBirth`, which the app merges onto the profile for showing an age (MVP2-124). HRmax is never read from HealthKit; default to Tanaka (`208 − 0.7 × age`) from `dateOfBirth`, raised later from workouts that exceed it (§2.1, MVP2-56).

Requested authorisations: read `workoutType`, `heartRate`, `restingHeartRate`, the distance types (`distanceWalkingRunning`, `distanceCycling`, `distanceSwimming`, `distanceRowing`) and the speed types (`runningSpeed`, `cyclingSpeed`; MVP2-146), `dateOfBirth`, `biologicalSex`. No write scopes in MVP 1.

### 5.2 `TrainingWorkoutKit`

```swift
struct WorkoutKitBridge {
    func customWorkout(from workout: StructuredWorkout) throws -> CustomWorkout
    func structuredWorkout(from plan: WorkoutPlan) throws -> StructuredWorkout
    func sync(_ workout: StructuredWorkout) async throws -> UUID       // returns WorkoutKit plan id
    func workoutPlan(for plan: PlannedActivity, workout: StructuredWorkout) throws -> WorkoutPlan  // id == plan.id
    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout) async throws  // replaces the plan's entry
    func unschedule(_ plan: PlannedActivity) async   // removes the plan's entry, whatever its date
    func unscheduleAll(except planIDs: Set<UUID>) async -> Int   // clears entries no plan names
}
```

- Mapping is mechanical: `WorkoutBlock` ↔ `IntervalBlock`, `WorkoutStep` ↔ `IntervalStep`, `StepGoal` ↔ `WorkoutGoal`, `IntensityTarget` ↔ `WorkoutAlert`.
- Sync is one-directional: library → WorkoutKit. A scheduled entry's `WorkoutPlan` id is its `PlannedActivity`'s id (MVP2-55), so each entry belongs to exactly one plan: a workout planned on several days, or twice on one day, gets a distinct entry each time, and a completed entry (or an `HKWorkout` started from one) names the plan it fulfilled. `StructuredWorkout.workoutKitID` isn't used for scheduling; it only records the plan a workout was recovered from.
- Scheduling a `PlannedActivity` uses `WorkoutPlan`'s schedule API; WorkoutKit only shows ±7 days on the Watch, so scheduling is done lazily for plans within that window rather than for the whole season.
- `schedule` first removes any entry with the plan's id, whatever its date, so moving a plan or editing its workout needs only another `schedule` call. An entry on the plan's own day is left alone when it's identical or already completed, so repeating the call is a no-op and never resets the Watch's completion flag. A completed entry is kept even if the workout was edited since: the athlete already did the version it holds.
- `unscheduleAll(except:)` removes entries whose id isn't a plan id: entries scheduled before MVP2-55 (random or library-workout ids, which nothing can match any more) and any a failed `unschedule` left behind. The caller passes the ids of every plan in the store, not just the loaded window.
- Calls go through `WorkoutScheduling`, an internal struct of closures over `WorkoutScheduler.shared` (which crashes outside an app bundle), so tests run the scheduling logic against an in-memory fake.
- Deleting a plan calls `unschedule`, which finds the entry among `WorkoutScheduler`'s own scheduled workouts by the plan's id and removes that, rather than rebuilding a `WorkoutPlan` — so a workout edited since scheduling still matches.
- Completed scheduled workouts can be queried back from WorkoutKit (date + completed flag, no health data). That's a cheap first signal for reconciliation before the HealthKit import lands.

### 5.3 Reconciliation (`TrainingCore`)

`PlanReconciler` links a completed `Activity` to a `PlannedActivity` on the same day with the same sport. An activity that names the plan it was started from (`scheduledPlanID`, read by the HealthKit importer from `HKWorkout.workoutPlan`, whose id is the plan's own) is matched to that plan first, exactly and without an ambiguity flag, when the plan is unmatched and on the activity's day (MVP2-120); earliest activity first. A hint for a missing plan or another day falls through to the heuristic; one whose plan is on the day but already taken (the second piece of a paused workout) leaves its activity unlinked rather than guessing another plan. With several candidates the best fit wins, judged on what the plan explicitly sets (total duration if every step has a time goal, distance if every step has a distance goal); an estimated duration is only a fallback. Assignment is best-pair-first across all activities of a day, and a close runner-up is flagged (`PlanMatchAmbiguity`) rather than silently resolved. Only newly imported activities are auto-matched, so a manual unlink sticks; a manual link (`TrainingModel.linkActivity`) is also same-day only. Sets `PlannedActivity.completedActivityID` and `Activity.linkedPlanID`. In MVP 1 this only affects the merge rule (today's actual beats today's estimate); in MVP 4 the `(expected, actual)` pairs it produces are the training data for calibration.

---

## 6. Directory layout

```
Sources/
  TrainingCore/
    Athlete/          AthleteProfile, HeartRateZoneModel, PaceModel, BiologicalSex
    Activity/         Activity, HeartRateSample, ActivitySource, Sport
    Load/             TrainingLoad, LoadCalculator, ExponentialTRIMPCalculator,
                      DurationRPECalculator, TRIMPCoefficients, LoadError
    Workouts/         StructuredWorkout, WorkoutBlock, WorkoutStep, StepGoal, IntensityTarget
    Planning/         PlannedActivity, PlannedLoadEstimator, TRIMPPlanEstimator, LinkedActivityRefinedEstimator, PlanReconciler
    Series/           DayLoad, DailyLoadSeries, FitnessMetrics, FitnessMetricsCalculator,
                      LoadModelParameters
    Evaluation/       PlanEvaluator, PlanEvaluation, PlanFinding, PlanGuardrails
    Statistics/       ActivitySummary, TimeInZone, PeriodStats, PeriodDelta, WeeklyStats,
                      CycleStats, CycleFitness, StatisticsCalculator, HeartRateSegmentIterator
    Cycles/           TrainingCycle, CycleLevel, CyclePhase, MicroLoadRole, MesocycleTemplate,
                      MacroTemplate, CycleLayoutBuilder
    Goals/            Goal, GoalTarget, GoalMeasure, GoalPeriod
    Store/            ActivityStore, PlanStore, TrainingPlanStore, WorkoutLibraryStore, CycleStore, RaceStore,
                      GoalStore, WorkoutTemplateStore, WorkoutTemplateStoreError, TemplateRemoval,
                      AthleteStore, FitnessMetricsCacheStore, InMemoryStore
    TrainingModel.swift
  TrainingHealthKit/  HealthKitActivityImporter, HealthKitAthleteReader, ImportAnchor
  TrainingWorkoutKit/ WorkoutKitBridge, WorkoutKitMapping+Goals, WorkoutKitMapping+Alerts
  TrainingPersistence/ SwiftData models, SwiftDataStores
  TrainingTools/      TrainingTool, ToolRegistry, ToolSchema, JSONSchemaEncoder, PlanSandbox,
                      Tools/ (one file per tool)
  TrainingToolsAnthropic/ AnthropicToolLoop, CoachSystemPrompt
  TrainingToolsFoundationModels/ FoundationModelsBridge
Tests/
  TrainingCoreTests/
```

---

## 7. Test plan (Core)

- **TRIMP**: constant-HR stream reproduces the closed-form value exactly; a two-segment stream (easy then hard) is greater than the same average HR held flat; empty stream throws; NaN/negative bpm rejected; gap handling.
- **Estimator**: a workout with only `.time` steps at fixed zones is deterministic; `.distance` steps respond to `PaceModel`; estimated load for a steady 60 min Z2 run lands within a sane band of the measured TRIMP for the same run.
- **Series merge**: past planned-but-undone day = 0; today with both actual and plan = actual; future = estimate; timezone boundary at 23:30 local doesn't leak an activity into the next day.
- **Metrics**: EWMA against hand-computed values; steady load converges to that load; `tsb` sign flips after a rest day; monotony `.nan` on flat week; seed offsets the first day correctly.
- **Reconciler**: same-day same-sport link, tie-break on duration, no cross-day links.
- **Cycles**: nesting/overlap rules rejected by `CycleStore`; `CycleLayoutBuilder` from a fixed start to a fixed race yields the expected sequence of phases, trims the first meso correctly, and a race less than one meso away degrades to taper + race only; cycle stats roll up micro totals into the meso exactly; recovery-vs-recovery delta picks the right sibling.

---

## 8. Plan generation & evaluation (MVP 2, guardrails defined in Core now)

The assistant in MVP 2 doesn't just emit a plan — it proposes one, runs it through the series engine, and checks the *projected* metrics against injury-risk and progress rules before accepting it. Because the evaluation is pure functions over `[FitnessMetrics]`, it belongs in `TrainingCore` and can ship in MVP 1 as a read-only "how does my current plan look" check.

### 8.1 Plan preferences (generator input)

`PlanGuardrails` (below) is the safety ceiling everyone shares; `PlanPreferences` is what one athlete actually wants, and it's what the generator proposes *from*. Preferences are soft — the generator honours them where it can, but backs off before it lets any proposal violate a guardrail. Versioning like `HeartRateZoneSettings` isn't needed here since a stale preference just produces a worse first proposal, not a wrong load calculation.

**Shipped so far (MVP5-104): run availability.** When the athlete can run is a fact about the athlete, not a choice for one plan, so it is its own value, `RunAvailability` (`slots: [Weekday: Set<DaySlot>]`, with `DaySlot` = `.morning` / `.afternoon` / `.evening`, see MVP5-129 below), reusing the existing `Weekday`. It is independent of the training paradigm and is stored as one global setting, `AthleteProfile.runAvailability`, synced with the other athlete preferences (`AthletePreferencesRecord`); `PlanPreferences.runAvailability` carries a copy as the generator's input (the generator will read the global setting and put it there). Weekdays without slots mean no running; how many runs a day gets is `runsPerDay` (MVP5-131), no longer inferred from the free parts (MVP5-119). Decoding is tolerant: missing fields default, unknown weekdays and slots are dropped.

**Shipped so far (MVP5-129): three day parts.** `DaySlot` has three cases, `.morning`, `.afternoon` and `.evening`, instead of two (the combined `.afternoonEvening` is gone as a case). Availability and the synced preferences record written with the old name keep their meaning: `RunAvailability` decodes a stored `afternoonEvening`, both as a free slot and as a key of `slotOptions`, to both `.afternoon` and `.evening`, carrying its options onto both; when options are stored under the old key and under a new name, the new name wins. It is written again only in the new form. The two-a-day is no longer inferred from the free parts: the number of runs is its own field (MVP5-131). The availability settings screen (MVP5-105, MVP5-128) is TrainingApp's.

**Shipped so far (MVP5-131): runs per weekday.** `RunAvailability` carries sparse `runsPerDay: [Weekday: Int]` (only days above 1 are stored; read through `runs(on:)`, write through `setRuns(_:on:)`), so availability stored before it, and the synced preferences record that holds it, decodes to one run a day. Counts of 1 or less are dropped on init and decode. `runs(on:)` is 0 on a day without free parts and otherwise the stored count capped at the number of free parts; the stored count is kept uncapped, so removing and re-adding parts restores it, as with `slotOptions`. The generator (MVP5-119) puts that many runs on the day, each in its own free part, and no longer infers a two-a-day from two free parts. The settings control is MVP5-132 (TrainingApp).

**Shipped so far (MVP5-127): per-slot options.** A free slot can allow more than a plain run, so `RunAvailability` carries sparse `slotOptions: [Weekday: [DaySlot: SlotOptions]]` beside `slots` (read and write through `availability[weekday, slot]`; `slots` and its encoding are unchanged). `SlotOptions` has `longRunPossible` (the slot leaves time for a long run, default `true`) and `trackAvailable` (a track is at hand, default `false`), so availability stored before the options existed, and the synced preferences record that holds it, decodes unchanged to the defaults and behaves as before. Slots at the defaults are not stored. The generator (MVP5-119) will put long runs only on slots with `longRunPossible` and track sessions only on slots with `trackAvailable`, falling back to another quality session when there is none; an interval session never requires a track. The generator rules are MVP5-119 and the settings toggles MVP5-128 (TrainingApp). The per-plan fields below move onto the per-plan `TrainingPlan` (MVP5-124) as they are added (MVP5-110).

**Shipped so far (MVP5-110): run types per weekday.** `RunType` (`recovery`, `easy`, `long`, `threshold`, `interval`) is what the athlete picks for a day; it maps to `IntensityCategory` (recovery → veryLow; easy, long → low; threshold, interval → high) and to the generic `SessionType` (recovery, easy, long, tempo, interval), which stays a small set because template specifics live in the `StructuredWorkout`. The choice is part of the athlete's weekly calendar, not of a plan, so `RunAvailability` carries sparse `dayRunTypes: [Weekday: Set<RunType>]` (read the effective types through `runTypes(on:)`, write through `setRunTypes(_:on:)`), stored and synced with the availability (`AthleteProfile.runAvailability`); a payload without it decodes to none named, and unknown run types are dropped. A day can name several types (Thursday: interval and threshold) and the generator (MVP5-119) decides which it places. Naming a type ties it to the days that name it, so a long run named for Sunday goes only on Sunday (or on Saturday too, if that names it as well, and the generator picks one or both); a type no weekday names is free and allowed on every running day, named or not (an easy run may replace the long run on Sunday, say to stay within a volume limit). `runTypes(on:)` is empty on a day without free slots, and for an unnamed day when every type is named elsewhere. The picker is MVP5-112 (TrainingApp), day assignment MVP5-119. The peak weekly volume is not part of this: it is `PlanPreferences.maxWeeklyVolume` (MVP5-133) and the plan's volume curve (MVP5-117) reads it.

**Shipped so far (MVP5-133): peak weekly volume.** `PlanPreferences.maxWeeklyVolume: [Sport: VolumeTarget]` is the most the athlete wants in any 7 days, per sport (a figure per 7 days whatever the micro length); a sport without an entry, and the default empty dictionary, mean no limit beyond the guardrails. `VolumeTarget` is a `VolumeMeasure` (`distanceMeters`, `durationSeconds` or `trimp`) with a positive, finite `amount`, built through a failable init; this shipped type replaces the earlier unit-plus-optionals sketch, and the other volume fields below will reuse it when they are added. It is a per-plan input, so it lives on `PlanPreferences` and moves onto `TrainingPlan` with the other per-plan fields, not on the athlete-level `RunAvailability`. Preferences are not stored by themselves yet, so no store or sync changes; the encoding is an array of `{sport, volume}` entries (`Sport` is not a string key), and decoding is tolerant: a payload without it means no limit, and entries with an unknown sport or measure or an invalid amount are dropped. The volume curve that reads it is MVP5-117 and the Create Plan wizard field MVP5-134 (TrainingApp).

**Shipped so far (MVP5-117): volume curve.** `VolumeCurveBuilder.targets(for:starting:peak:)` turns a laid-out plan (`[Microcycle]`) into one `MicroVolumeTarget` per micro, in the measure of `starting` and `peak` (both per 7 days, scaled by micro length so 7-, 10- and 14-day micros read alike; the caller passes the peak, capped by `maxWeeklyVolume` if the athlete set one). Build micros climb linearly from the starting volume at the first build micro to the peak at the last (a single build micro gets the peak); a recovery micro holds `recoveryLoadFraction` (0.6) of the preceding build micro; taper micros step down linearly from 0.7 to 0.5 of the peak (one taper micro: 0.6); the race micro gets 0.3. The fractions are design defaults, settable on the builder. It throws `VolumeCurveError` for a mismatched measure, a peak below the start or a bad fraction. The curve is the plan before the guardrails: the adjust loop (MVP5-120) lowers micros where `PlanEvaluator` asks and reports the volume reached. A conditioning phase's start fraction and ramp are not part of it yet.

**Shipped so far (MVP5-111): key races.** `KeyRaceLayout` (`secondaryTaperMicros`, `secondaryRecoveryMicros`, both 1 by default, counted in micros so 7-, 10- and 14-day micros work) lays out the micros with `CycleLayoutBuilder` back from the primary race and then applies the other races' priorities by changing load roles only, so no micro is added and phases, meso blocks and the primary taper stay put. A secondary race makes the micro with race day `.taper` (there is no race role: `CycleLayoutBuilder` now gives the primary race's last micro `.taper` too; `MicroLoadRole.race` stays so stored micros decode) and the next micros `.recovery`; if race day is the first day of a micro, that micro is the first recovery and the taper ends the micro before. Tertiary races (and other primaries) change nothing and are not reported. `microcycles` and `layout` return `KeyRaceMicrocycles` / `KeyRaceCycles` with a `KeyRaceAdjustment` per secondary race, in date order: `applied(taperMicros:recoveryMicros:)` (shortened by the layout start, the primary taper or a neighbour) or `skipped` with `outsideLayout` (before the first micro or after the primary race), `insidePrimaryTaper` (also race day itself) or `tooCloseToEarlierRace` (same micro as an earlier secondary race or in one its taper claims). When two secondary races are close the earlier race keeps its taper and the later taper takes the earlier recovery. The pure `apply(to:primary:races:athlete:)` works on micros already laid out. `VolumeCurveBuilder` treats the last micro as the race micro when its role is `taper` (or `race`, for stored plans): it gets `raceFraction` and stays out of the taper ramp, so race-week volume is unchanged by dropping the role. Taper and recovery lengths are not read from the paradigm or the race distance yet; the app's race picker is MVP5-135.

**Shipped so far (MVP5-114): specific-phase intensity target.** `SpecificPhaseTarget` is what a race's specific-phase work is aimed at, stored on `Race.specificPhaseTarget` (optional; `nil` means no target). One enum of four kinds: `.pace(secondsPerKilometer:)` (a goal pace for the race distance; per-mile display is the app's job), `.heartRate(beatsPerMinute:)` (a closed range, equal bounds for a single value), `.perceivedEffort(_:)` (Borg CR10, 1...10) and `.predictedFromFitness`, a placeholder with no prediction model behind it yet. `validate()` throws `SpecificPhaseTargetError` for a non-finite or non-positive pace or heart rate, or an effort outside 1...10, and decoding validates. `Race` decodes tolerantly: a payload without the field, or with an unknown or invalid target, keeps the race and decodes the target to `nil` (a `Race` is synced, so an older device must still read a newer one's race). `Goal` is untouched: it has no date and no link to a plan. Only `StepTargetResolver` reads the target so far (MVP5-122, a `.pace` target; see "Step targets" below) and the generator's use of it (including what it does without one) is later. The editor is TrainingApp work.

**Shipped so far (MVP5-119): day assignment.** `DayAssigner.assign(micro:availability:hardCount:longCount:preceding:calendar:)` places one micro's runs on its days and day parts and returns a `DayAssignmentResult` (`assignments: [DayAssignment]` of day, `DaySlot` and `RunType`, and `dropped: [DroppedSession]` with a `DropReason`). The athlete states how many hard and how many long sessions a micro gets; every other free run (`runs(on:)` per day) is filled with an easy run, or a recovery run where easy is not allowed on that day. Order: long runs first (a day that allows `.long` and has a part with `longRunPossible`; days naming `.long` first, then more free parts, then the earlier date), then hard sessions (a day that allows one of `hardTypes`, default interval then threshold; days naming a hard type first, then the earlier date), then easy. A day allows a type per `RunAvailability.runTypes(on:)`. With a paradigm, hard sessions (and long runs if `spacesLongRunsAsHard`) keep `minDaysBetweenHardSessions` from each other and from `preceding`, and a micro gets no more hard sessions than `maxHardSessionsPerMicro` allows for its length. Weekdays map by date, so 10- and 14-day micros reuse weekdays. A session that cannot be placed is returned as dropped (`noFreeDay`, `runTypeNotAllowed`, `noLongRunSlot`, `spacing`, `hardLimit`), never substituted; the generator (MVP5-145) reports each as a compromise. A run takes the first free part in morning, afternoon, evening order (a long run the first one where a long run is possible). Track availability is ignored, since no run type needs a track.

**Shipped so far (MVP5-138): ultra target.** Ultra is a property of the target, not a paradigm. Every `Race` now has a required `distanceMeters` (finite, above zero; a personal target such as "run 50 km" is also a `Race`, only not an organised one, and the UI should say so); `Race.isUltra` is a distance above a marathon (42,195 m). A stored race without a distance does not decode: the SwiftData store skips and logs it, as it does for goals. `TrainingParadigm` gains two optional settings, `maxLongRunMeters` (a ceiling on the long run in meters, default 35 km, `nil` for none; read by the generator, MVP5-117/118, no rule checks it yet) and `maxBackToBackLongRunPairsPerMicro` (by micro length, like `maxHardSessionsPerMicro`; no entry means no limit). `TrainingParadigm.resolved(for: targetRace)` returns the paradigm for the plan: for an ultra `spacesLongRunsAsHard` is `false` and the two settings stay; for any other race, or none, they are dropped. `PlanEvaluator.evaluate(...targetRace:)` and `DayAssigner.assign(...targetRace:)` resolve the paradigm that way, so the spacing rule ignores long runs for an ultra, and the assigner places long runs on consecutive days but at most the limit's number of such pairs per micro (a long run that would add one over the limit is dropped as `spacing`). A pair is two long runs on consecutive days, both marked long (`DayAssigner.assign(precedingLongRuns:)` counts a long run just before the micro, so a pair across a micro boundary is limited too); invalid ceilings and negative pair limits in a paradigm are cleaned to none and zero; the second is not a hard session and a pair does not count towards `maxHardSessionsPerMicro`. The athlete can set their own ceiling: `PlanPreferences.maxLongRunMeters` (optional, per plan, invalid values read as none; the app asks for it when the plan has an ultra target), and `PlanPreferences.maxLongRun(for:targetRace:)` returns the effective one: nil unless the target is an ultra, then the athlete's value (even above the paradigm's) or else the paradigm's 35 km default. Intensity targets and hard-session limits of the base paradigm are unchanged for an ultra. Both built-ins allow 1, 1 and 2 pairs per 7-, 10- and 14-day micro; the 35 km ceiling is the default of every paradigm. The evaluator does not flag a long run above the ceiling or too many pairs. Needs from the app: pass a distance wherever it creates a `Race`, show a personal distance target as a goal rather than a race with competitors, and pass the plan's target race to the evaluator and the assigner.

**Shipped so far (MVP5-139): where `PlanSession.isLongRun` comes from.** The evaluator works on `PlanSession` values, and nothing converts a `PlannedActivity` to one except `PlannedIntensityClassifier.session(on:for:athlete:)`, so the flag has one source: the workout's own tag. `StructuredWorkout` and `WorkoutTemplate` carry an optional `sessionType: SessionType?` (a template gives it to the workouts it instantiates, like `purpose`; `nil` is untagged and never a long run; an old payload, and an unknown value from a newer one, decode as `nil`; the calendar file keeps it as the optional string `sessionType`). `StructuredWorkout.isLongRun` is `sessionType == .long`, and `session(on:for:athlete:)` sets `PlanSession.isLongRun` from it (its former `isLongRun:` parameter is gone). Not the source: the day, the length, or the athlete's `dayRunTypes`. The data flow for the generator (MVP5-118/120): `DayAssigner` decides *where* a long run goes and returns `RunType.long` assignments; for each one the generator picks a library workout tagged `RunType.long.sessionType` (`SessionType.long`); the evaluator then reads the flag off that workout. The two agree only through that choice, and the generator owns it. Where they disagree the tag wins for the rules: a long-tagged workout on a day the athlete did not name `.long` is a long run (spaced like a hard session, or not for an ultra, and counted for pairs), and an untagged workout on a `.long` assignment is not, which the generator should avoid by falling back to the closest tagged match and reporting it as a compromise. A long run the assigner dropped has no workout and so no flag. A tag value from a newer version reads as untagged and is lost if this version re-saves the workout (unlike `purpose`, which fails to decode); a workout built from a calendar-file entry without a template is untagged. Library and template tagging, and the picker that chooses which workout fills a slot, are not part of this; no built-in template is tagged yet.

**Shipped so far (MVP5-115): short lead time.** `LeadTimeCompromiser` is a pure step between the paradigm and `CycleLayoutBuilder`: it takes the paradigm's full-length `MacroTemplate`, the lead time in days and the micro length (7, 10 or 14), and returns a `LeadTimeAdjustment` (the macro to lay out and `[LeadTimeCompromise]`). Only whole micros count (`leadTimeDays / microLengthDays`; the remainder is not planned), and every micro counts as `microLengthDays`. While the macro is longer than that, the steps run in this order: (1) drop the conditioning phase, (2) drop the structural phase, (3) shorten the paradigm's `shortenablePhase` (triphasic `.specific`, polarized `.peak`; `nil` for a paradigm without one) down to `minimumShortenedMicros` in total (default 1, a property of the compromiser), earliest block first, (4) trim the oldest remaining blocks (the taper and the shortenable phase stay). The taper (`.taper` and `.race` phases) is never shortened. If the lead time is below the taper plus the shortest allowed shortenable phase there is no plan: `adjust` throws `LeadTimeError.leadTimeTooShort(availableMicros:requiredMicros:)` (also `invalidMicroLength` and `negativeLeadTime`). A macro that fits is returned unchanged. Conditioning is an athlete setting, `PlanPreferences.includeConditioning` (default `false`, old payloads decode to `false`): when false conditioning blocks are removed whatever the lead time and nothing is reported; when true it is kept while there is room and dropping it is reported with `overriddenPreference == .includeConditioning`. Each change is a `LeadTimeCompromise` with an `Action` (`phaseDropped`, `phaseShortened(from:to:)`, `oldestPhaseTrimmed(from:to:)`; lengths in micros) and a `Reason` (`leadTimeTooShort(availableMicros:neededMicros:)`, where needed is the macro's length at that step), in the order made. `TrainingParadigm.shortenablePhase` is new (optional, decoded tolerantly). Compromises are not findings yet: the plan proposal and the `.warning` findings (MVP5-120) and the preview (MVP5-121) read them. Conflicts of a preference with the shortened plan other than conditioning (an unreachable `maxWeeklyVolume`, thin availability) are not detected here.

```swift
struct PlanPreferences: Sendable, Codable {
    var trainingDays: Set<Weekday>                    // which days the athlete trains; count = sessions/week
    var dayPreferences: [Weekday: DayPreference] = [:] // optional per-day sport/surface/session-type preference
    var maxWeeklyVolume: [Sport: VolumeTarget] = [:]   // shipped (MVP5-133): peak per 7 days; empty = no limit
    var maxLongRunMeters: Double?                      // shipped (MVP5-138): ultra long-run ceiling; nil = paradigm's
    var includeConditioning: Bool = false              // shipped (MVP5-115): keep the conditioning phase if there is room
    var startingSessionVolume: VolumeTarget            // week-1 default: distance/duration of a regular
                                                        // (non-long, non-special) session
    var maxSingleSessionDistanceMeters: Double?        // long-run cap; nil = no cap beyond guardrails
    var maxSingleSessionDuration: TimeInterval?        // cap for time-based steps/sports
    var startingWeeklyVolume: VolumeTarget             // week-1 target: total distance or duration
    var weeklyIncrement: VolumeIncrement                // how fast volume ramps toward the meso target
}

struct DayPreference: Sendable, Codable {
    var sport: Sport?              // defaults to the athlete's primary sport if nil
    var surface: RunSurface?       // .road, .trail, .track, .indoor; nil = no preference.
                                    // Overlaps Venue (MVP2-151): derive it from Venue, or replace it, when built
    var sessionType: SessionType?  // e.g. .long on Sunday, .interval on Tuesday, .hillRepeats on Thursday;
                                    // nil = generator picks freely (typically .easy)
}

enum RunSurface: String, Sendable, Codable {
    case road, trail, track, indoor
}

struct VolumeTarget: Sendable, Codable, Hashable {     // shipped in MVP5-133
    let measure: VolumeMeasure     // .distanceMeters, .durationSeconds or .trimp
    let amount: Double             // positive and finite, in the unit of the measure
    init?(measure: VolumeMeasure, amount: Double)   // nil for non-positive or non-finite amounts
}

struct VolumeIncrement: Sendable, Codable {
    var amountPerWeek: Double?     // absolute increase, same unit as the target
    var percentPerWeek: Double?    // relative increase (e.g. the "10% rule"); wins if both are set
}
```

`PlanGenerator` reads `trainingDays` to decide which calendar days get a session at all, and `startingWeeklyVolume` + `weeklyIncrement` to size each week's total before splitting it across sessions. Days without a `dayPreferences` entry (or with `sessionType == nil`) default to an `.easy` session sized from `startingSessionVolume`, ramped the same way as the weekly total. Days with an explicit `sessionType` (e.g. `.long` on Sunday, `.interval` on Tuesday, `.hillRepeats` on Thursday) are filled from library workouts matching that `sessionType`/`sport`/`surface`, falling back to the closest match if the library has nothing tagged for it. `maxSingleSessionDistanceMeters`/`Duration` bounds any one session — most relevant to `.long` days — regardless of what the ramp would otherwise assign; this is a preference-level cap (e.g. "I don't want a long run over 32km"), independent of and typically tighter than anything `PlanGuardrails` enforces at the series level. None of this bypasses §8.2: a ramp the athlete asked for that would still breach a guardrail (e.g. `minAcceptableTSB`) gets throttled by the same adjust step as any other proposal.

### 8.2 Guardrails

```swift
struct PlanEvaluation: Sendable {
    let findings: [PlanFinding]
    var isAcceptable: Bool { !findings.contains { $0.severity == .risk } }
}

struct PlanFinding: Sendable {
    let day: Date
    let rule: PlanRule
    let severity: Severity            // .info, .warning, .risk
    let value: Double
    let threshold: Double
}

struct PlanGuardrails: Sendable, Codable {
    var maxMonotony: Double = 2.0
    var maxStrainPercentile: Double = 0.95     // relative to athlete's own trailing 12 weeks
    var minTSBOnRaceDay: Double = 5
    var maxTSBOnRaceDay: Double = 25
    var minAcceptableTSB: Double = -30         // any day
    var maxAcceptableTSB: Double = 25          // any day
    var strainTrailingWindowDays: Int = 84
    var maxLongestRunIncreaseFraction: Double = 0.10   // a run vs the longest earlier run
    var longestRunLookBackDays: Int = 28
}

struct PlanEvaluator: Sendable {
    func evaluate(_ metrics: [FitnessMetrics], races: [Race],
                  guardrails: PlanGuardrails) -> PlanEvaluation
}
```

Rules, all computed from the projected series:

| Rule | Signal | Why |
|---|---|---|
| Monotony | 7-day mean / stdev | > 2.0 means the week has no easy/hard contrast, even at moderate volume |
| Strain | weekly load × monotony | Absolute thresholds don't transfer across athletes in TRIMP units, so compare against the athlete's own trailing distribution |
| Race-day TSB | TSB on `Race.date` | Taper landed: positive but not so high that fitness was lost (a warning, not a risk) |
| TSB band | TSB on any day | Below `minAcceptableTSB` (−30) is the injury-risk band; above `maxAcceptableTSB` (25) reads as detraining (a warning) |
| Longest run | a run's planned duration vs the longest run of the previous 28 days (any type, the day itself excluded) | at most +10 % (`maxLongestRunIncreaseFraction`) within `longestRunLookBackDays` (28); a chain of runs each within the limit of the last passes; risk; a run with no earlier run in the look-back is not checked; needs `sessions`, not cycles |
| Paradigm rules | intensity distribution, hard-session spacing, hard sessions per micro | only with a `TrainingParadigm` (see "Paradigm rules" below) |

Earlier iterations also had a CTL-ramp rule (CTL[d] − CTL[d−7]), an ATL/CTL ratio, and cycle-aware recovery-micro, meso-progress, taper-shape and consecutive-load rules. They were removed (MVP5-101 review) as thresholds nobody had asked for; ramp control is left to the generator's own volume curve (MVP5-117) and the longest-run rule. Only `.risk` findings make a plan unacceptable, so a missed race-day TSB or an over-high TSB is reported but doesn't by itself send the generator back to adjust.

#### Paradigm rules (MVP5-102)

A `TrainingParadigm` (name, `phases: [CyclePhase]` in order, `guardrailOverrides: PlanGuardrails.Overrides`, the settings below) turns on three more rules. They run only when `PlanEvaluator.evaluate(_:races:cycles:guardrails:sessions:paradigm:targetRace:)` gets a paradigm; without one the result is exactly as before. The paradigm's overrides are applied on top of `guardrails` first. `PlanGuardrails.Overrides` is a struct of optionals, one per threshold; a `nil` field leaves the default.

The rules read `sessions: [PlanSession]` (day, planned seconds, `IntensityCategory`, `SpeedLevel`), so the evaluator stays a pure function. Two independent scales describe a session: **intensity** (from time in zones, §intensity classification) and **speed** (`slow`/`moderate`/`fast`/`max`, the highest zone of the work steps, however short; `PlannedIntensityClassifier.speedLevel(of:athlete:)`). Hill sprints are `low` intensity but `max` speed.

| Rule | Signal | Check | Severity |
|---|---|---|---|
| `intensityDistribution` | per micro, share of planned time per intensity category and per speed level | each *listed* share within `tolerance` of its target in the phase's `IntensityMix` (`phaseMixes[phase]`, else `defaultMix`); polarized 80/20 lists `.high: 0.2` (build 0.22, peak 0.25) and `.medium: 0`, leaving `.low`/`.veryLow` as the easy remainder; a base phase of easy runs lists `.medium`/`.high` at 0 | warning |
| `hardSessionSpacing` | days between consecutive hard sessions | at least `minDaysBetweenHardSessions` (Tue to Thu is 2; `nil` = off) | risk |
| `hardSessionsPerMicro` | hard sessions in a micro | at most `maxHardSessionsPerMicro[length in days]`; a length with no entry is not checked, so 7-, 10- and 14-day micros are set independently | risk |

**Built-in paradigms (MVP5-103)** are static `TrainingParadigm` values, `TrainingParadigm.builtIn` lists them; they hold rules data only (layout such as micro length, meso pattern and phase lengths belongs to the generator):

| | `polarized8020` | `triphasic` |
|---|---|---|
| Phases | base, build, peak, taper | conditioning, base, structural, specific, taper (`CyclePhase.conditioning/.structural/.specific`) |
| Distribution (per micro, ±0.05) | `high` 0.2 (build 0.22, peak 0.25), `medium` 0; `low` and `veryLow` unlisted, so both are the easy remainder | conditioning: `medium`/`high` 0, speed `moderate`/`fast`/`max` 0; base: `medium`/`high` 0, speed `moderate`/`fast` 0 (slow running and max-speed sprints allowed); structural: `high` 0.10 and `fast` 0.10, `medium`/`moderate` 0, ±0.10; specific and taper: `medium`, `high`, `moderate`, `fast` each 0.25, ±0.25 (none above 50 %); no ceiling on `max` in base (MVP5-137) |
| Hard | intensity ≥ `high` | intensity ≥ `high` or speed `max` (so 8 s sprints are placed like a hard day) |
| Spacing | at least 2 days; long runs are spaced like hard sessions (`spacesLongRunsAsHard`) | at least 3 days (Tue to Fri); long runs likewise |
| Hard per micro | 7 d: 2, 10 d: 3, 14 d: 4 | no limit (the athlete sets sessions per micro) |

The polarized numbers were reviewed in MVP5-136, kept except the build and peak `high` targets: they are product choices, not taken from a source apart from the 80/20 split (Fitzgerald). Shares are of whole-session planned time under each session's one intensity category, so a hard session's warm-up and cool-down count as hard time; build and peak allow more hard time (0.22, 0.25), set in MVP5-136. `PolarizedNumbersTests` pins every value and its boundary.

The triphasic numbers were set with the user on 2026-10-22 (MVP5-137), from the Run Elite skills where they speak and by the user's choice where they do not; the table of each number, its old value and its reason is in [triphasic-design.md](triphasic-design.md) §10, and `TriphasicNumbersTests` pins every value and boundary. Tolerance doubles as the width of an "at most" range (target 0.10 ± 0.10 is 0 to 20 %); the categories of a mix are checked separately, so their sum is not capped.

Long runs (`PlanSession.isLongRun`, set from the workout's `sessionType` tag, MVP5-139) are spaced like hard sessions but do not count towards the per-micro maximum. For a plan aimed at an ultra (a `Race` longer than a marathon, `Race.isUltra`) `TrainingParadigm.resolved(for:)` sets `spacesLongRunsAsHard` to `false`, because full-length long runs are not possible (MVP5-138, §10). A paradigm may name the race distance its numbers were calibrated for (`calibratedDistanceMeters`; 42,195 for triphasic, `nil` for polarized and for stored paradigms without it). `PlanAdjuster` sets `PlanProposal.calibrationWarning` (a `CalibrationWarning` carrying both distances) when the target race is more than 2 % from that distance and is not an ultra (decided 2026-10-22, Q19 in [triphasic-design.md](triphasic-design.md), MVP5-143). Example, a 20:00 5K: base endurance 0.80-0.85 is 4:42-5:00/km, moderate for that runner. It is a notice for the app, not a `PlanFinding`, and never affects `isAcceptable`; without a target race there is none. The structural and specific session profile numbers (interval work lengths, race-target fractions) are written down in [triphasic-design.md](triphasic-design.md) (MVP5-100), which also lists where the skills and the code differ; the numbers were dialled in MVP5-137, and the type that holds the profiles is `SessionProfile` (MVP5-118, below).

#### Template fit (MVP5-118)

A phase asks for sessions as data: `TrainingParadigm.sessionProfiles[phase]` is a list of `SessionProfile` (a `SessionType`, and optionally a work-length range in seconds, a work-count range and a `raceTargetFraction` that `StepTargetResolver` (MVP5-122) turns into step targets). A profile is a request, not a `PlanSession`. The built-in paradigms carry none yet (the generator then fits a profile with the session type only); the triphasic profile numbers are not decided (the questions are in [triphasic-design.md](triphasic-design.md) §9).

`WorkoutTemplate.analysis(athlete:)` reads what a template contains, the athlete's own as much as a built-in one: it instantiates the template with every parameter at the low end of its range and at the high end (every step grows with its parameters) and reports the shortest and longest *hard work step* (`.work` at zone 3 or higher, or RPE 7 or more, or `.work` at zone 2 in an interval set: a block repeated by a parameter or more than once that also has a recovery step, so 6 × 1 mile at zone 2 counts and an easy run's zone 2 body does not; pace, power and heart-rate-range targets are not counted), the work count, the total work time and the total duration. Distance steps are timed with the pace model, so the analysis needs the athlete.

`TemplateFitter.fit(profile:targetSeconds:templates:previous:workLength:athlete:)` is pure and returns `.fit(TemplateChoice)` or `.missingTemplate(SessionProfile)`, which the generator (MVP5-145) reports as a compromise:

1. *Hard filter*: running, not archived, tagged with the profile's session type (an untagged template never matches; the built-in templates are tagged since MVP5-118), and work length and count overlapping the profile's ranges when it gives them.
2. *Closest fit*: the parameters of hard work steps are set to the work length asked for (clamped to their range; distance steps are solved through the pace model), then the volume parameters (the duration or distance of the easy work steps) or, when there are none, the repetitions (limited to those within the work-count range) are chosen for the duration nearest `targetSeconds`. Other parameters, such as a recovery, keep their default. Ranking is lexicographic: relative duration error, then name, then id.
3. *Rotation*: if the best template was used in the previous micro (`previous`), the best other one replaces it when its error is at most 10 percentage points worse. No seed, no state beyond `previous`.
4. *Progression*: `SessionProfile.progressedWorkLength(microIndex:of:)` steps the work length linearly from the low to the high end of the range across the micros of a phase; the repetitions then follow the micro's volume, so the volume curve bounds the session. The result goes in as `workLength`.

Example: a profile of intervals with work 180 to 300 s and a 3600 s target excludes *Short interval run* (30 to 120 s); *Long Interval Runs* gets `work = 240`, `reps = 6` (3420 s, 5 % off). The caller turns a micro's `MicroVolumeTarget` into the target seconds of each session; the fitter does not size sessions itself.

A session is *hard* when its intensity is at least `hardIntensity` (default `.high`) or, if the paradigm sets `hardSpeed`, its speed is at least that, so a paradigm can put max-speed easy runs on the hard days while the distribution still counts their time as easy. The distribution and per-micro rules need `cycles`; spacing does not. `PlanFinding.subject` names the category or level a distribution finding is about (`"intensity.high"`, `"speed.max"`). Boundaries pass (a share exactly at the tolerance, a count exactly at the maximum). The built-in paradigms (80/20 polarized, triphasic) are MVP5-103.

Guardrail values are `Codable` and user-editable; MVP 4 can tune them from observed outcomes (e.g. the athlete who tolerates a lower TSB without issue).

#### Adjust loop and plan proposal (MVP5-120)

The generator loop is: build a plan (a `PlanCandidate`: cycles, planned workouts, `PlanSession`s, the projected series from `DailyLoadSeries` and `FitnessMetricsCalculator`, and the provider's compromises) → `PlanEvaluator` → while a `.risk` remains, try one `PlanAdjustment` → repeat. The plan generator itself (`PlanGenerator`, MVP5-145, see "Plan generator" below) is not part of the loop: it sits behind `PlanCandidateProvider`, which receives `PlanLevers` (volume factor per micro, down-week micros, eased days, dropped days) and today's date, and rebuilds the plan with them. `PlanAdjuster` never edits workouts, so the same loop serves any generator, and tests use a stub.

Each step takes the first risk finding (chronologically) with an untried adjustment and applies the gentlest one for its rule: `tsbBand` and `strain` → lower the micro's volume by a step (x0.9, floor 0.5), then make it a down-week; `longestRun` → lower the micro's volume, then drop the session; `hardSessionsPerMicro`, `hardSessionSpacing` and `monotony` → ease the session, then drop it. The old "throttle the requested ramp" is the volume step now that the volume curve owns the ramp. An adjustment is kept when the risks become fewer, or stay as many but sit closer to their thresholds; otherwise it counts as tried and is discarded. A set of levers is never built twice, so the loop cannot oscillate. It stops when the plan is acceptable, when nothing untried is left (`noAdjustmentLeft`) or after `maxIterations` (default 8) adjustments (`iterationLimit`), and then returns the plan as it stands, `isAcceptable == false`, with its findings.

`PlanProposal` holds the candidate, the `PlanEvaluation` (every severity), the compromises, the levers, the history of tried adjustments (`PlanIteration`) and the outcome. `risks` and `warnings` are separate views; warnings (race-day TSB, a high TSB, intensity distribution) are surfaced for the app to show and never block the proposal or send the loop back to adjust. `PlanCompromise` lists what was given up: the lead-time changes of MVP5-115, sessions `DayAssigner` could not place (with their `DropReason`), a `missingTemplate(SessionProfile)` from `TemplateFitter`, an overridden preference, and the adjustments the loop kept. `draftPlan(named:)` makes the `TrainingPlan` (draft) and `stamped(with:)` sets its `planID` on the cycles and workouts; previewing and committing is described under "Preview and commit" below.

MVP 3 adds an LLM-driven coach that can propose the same kind of edits conversationally, but it drives the identical `PlanEvaluator` gate rather than replacing it.

#### Preview and commit (MVP5-121)

`PlanCandidate.workouts` carries the `StructuredWorkout`s the planned workouts refer to (`TemplateFitter` makes them). `TrainingModel.preview(_:asOf:)` returns a `PlanPreview`: the proposal's cycles, planned workouts, workouts, projected form, compromises, risks and warnings, plus what activation would replace: the active plan, its planned workouts from today on that no activity has completed, and whether it is followed (a followed plan is cancelled with a date, an unfollowed one becomes a draft, as in MVP5-124; nothing is deleted). `TrainingModel.commit(_:named:activate:acceptingRisks:asOf:)` checks that every planned workout has a workout (in the proposal or the library: `PlanProposalError.missingWorkouts`), that no proposal workout would overwrite a different library workout (`workoutIDCollision`) and that no planned workout names a cycle the proposal lacks (`danglingCycleReferences`), all before anything is written, then saves the workouts, inserts the draft plan with its cycles and planned workouts in one write (they get fresh ids, parents and cycle references remapped, so committing a proposal twice makes two independent plans), and with `activate` activates it. A proposal with risks can be saved as a draft; activating it throws `PlanProposalError.hasRisks` unless `acceptingRisks` is set. The workout save, the plan insert and the activation are separate writes; a failure after the first leaves harmless library workouts, after the second a draft. The screens are the app's (TrainingApp).

#### Plan generator (MVP5-145)

`PlanGenerator` is the `PlanCandidateProvider` the adjust loop was built for: `PlanGenerator.generate(_ request: PlanRequest) async throws -> PlanProposal` runs `PlanAdjuster` with the generator itself as provider, so there is one seam and no second one. It adds no training logic and no numbers: every choice is in the `PlanRequest` or in a piece it composes. The request holds the target race and the other races, the paradigm, the full-length `MacroTemplate` and the `MesocycleTemplate` (which sets the micro length), `PlanPreferences` (availability, `maxWeeklyVolume`, `includeConditioning`), the athlete, `today` and `start`, the workout templates, the starting and peak weekly volume (both `VolumeTarget`s in `durationSeconds`), the hard sessions and long runs asked per micro, the past activities and recent `PlanSession`s, and the existing settings of the pieces (guardrails, `KeyRaceLayout`, `LeadTimeCompromiser`, `VolumeCurveBuilder`). The plan being replaced is not in it: the projected series ignores a replaced plan, as only the active plan feeds it, and `TrainingModel.preview` shows what a commit would replace.

Data flow of one candidate, built from scratch for a set of `PlanLevers` (a pure function of request and levers):

```
PlanRequest ──► LeadTimeCompromiser.adjust(macro, lead time = start...race day inclusive, meso length)
                 │  macro that fits, [LeadTimeCompromise]  (+ overriddenPreference(.includeConditioning))
                 ▼
               KeyRaceLayout.microcycles(start → target race, all races)   secondary races: taper + recovery micros
                 │  [Microcycle] (phase, MicroLoadRole)          levers.downWeeks: role → .recovery
                 ▼
               CycleLayoutBuilder.cycles(from:) ──► macro, meso, micro TrainingCycles (fresh ids)
                 ▼
               VolumeCurveBuilder.targets(starting, peak ≤ maxWeeklyVolume) ──► MicroVolumeTarget (seconds)  × levers.volumeScales
                 ▼  per micro, in date order
               DayAssigner.assign(hard, long, preceding hard/long days of earlier micros)
                 │  [DayAssignment], [DroppedSession] → PlanCompromise.unplacedSession
                 │  levers.droppedDays: run left out; levers.easedDays: hard or long run → easy
                 ▼  per run: share = micro seconds / runs of the micro
               SessionProfile (paradigm.sessionProfiles[phase] for the run's session type, else the type alone)
                 │  .progressedWorkLength(position of the micro in its phase)
                 ▼
               TemplateFitter.fit(profile, share, templates, previous = last micro's templates)
                 │  .missingTemplate → PlanCompromise.missingTemplate, run left out
                 ▼  TemplateChoice (template, values)
               WorkoutTemplate.instantiate ──► StepTargetResolver.resolve(race target, profile.raceTargetFraction)
                 ▼
               PlannedActivity(cycleID = micro) + StructuredWorkout ──► PlannedIntensityClassifier.session ──► PlanSession
                 ▼
               DailyLoadSeries(activities + planned workouts, TRIMPPlanEstimator, today) → padded to race day
                 → FitnessMetricsCalculator ──► PlanCandidate(cycles, plannedActivities, workouts, sessions, metrics, compromises)

PlanAdjuster: PlanEvaluator(candidate) → risk? → one PlanAdjustment → PlanLevers → candidate again (≤ 8) → PlanProposal
              (+ calibrationWarning from the paradigm and the target race)  →  TrainingModel.preview / commit → TrainingPlan with planID
```

Decisions (2026-10-22, with the user): the entry point is one request struct and `generate(_:)`, async because the seam is, and cancellable (checked before each candidate and each micro; a cancelled run throws `CancellationError` and returns nothing). Nothing reads the clock or a random source: the same request gives the same dates, templates, parameter values, sessions and series, and the ids of cycles, workouts and planned workouts are fresh `UUID`s (made inside `CycleLayoutBuilder` and `WorkoutTemplate.instantiate`), so two runs differ in ids only. Rotation memory is the previous micro's templates, rebuilt in every candidate. The first plan's metrics come from the same `DailyLoadSeries` and `FitnessMetricsCalculator` the model uses, so without history in the request the first 42 days are warming up and the TSB rules skip them (and a strain percentile has no past to compare with; an empty-history request typically ends at the iteration limit); the loop may change only the levers.

Errors, where nothing can be proposed (`PlanGeneratorError`): the lead time is shorter than the taper plus the shortest specific phase (or the micro length or lead time is invalid), the race is before the start or the layout is empty, the volume curve is invalid (peak below start, a `maxWeeklyVolume` in another measure than the request's), the volume is not in seconds, or a chosen template cannot be instantiated. Compromises, where the proposal is still returned: the lead-time changes, a requested session with no day (`unplacedSession`, with its `DropReason`), a profile no template meets (`missingTemplate`, the run is left out), a dropped conditioning phase against the athlete's wish and a micro whose fitted runs exceed `maxWeeklyVolume` (`overriddenPreference`). Sizing: the micro's seconds are split equally over its runs, as no rule for a share per run type exists; the built-in paradigms carry no session profiles yet, so their runs get a profile with the session type only, and a triphasic plan has generic intervals and tempo runs in its structural and specific phases until the profiles of [triphasic-design.md](triphasic-design.md) are decided. Every micro asks for the same number of hard sessions and long runs, whatever its role; the volume curve and the adjust loop do the lowering. The runs of one day share the start of that day as their date; the day part is not stored in a `PlannedActivity`.

Not reported, and listed as follow-ups: steps `StepTargetResolver` could not resolve (`UnresolvedStep`), secondary races `KeyRaceLayout` skipped (`KeyRaceAdjustment`), a plan that starts later than `start` because the macro is shorter than the lead time (the layout starts at the first micro it can fill), and a long run over `PlanPreferences.maxLongRun(for:targetRace:)` (a fitted run has no distance yet). `PlanCompromise` has no case for the first three; adding them is a request to the user, not part of MVP5-145. Distance and TRIMP volumes need a conversion to seconds that does not exist. `DayAssigner.preceding` takes the hard and long days of the plan's own earlier micros only, not those of `recentSessions`. The app wizard (MVP5-121, TrainingApp) and re-plan from today (MVP5-123) build on this.

---

## 9. Statistics (Core)

Descriptive stats sit next to the load model, not inside it — they share the same activities and zone model but never feed CTL/ATL. Pure functions in `TrainingCore/Statistics/`, computed on demand from the store (cheap enough not to persist; a cache keyed on activity IDs is a later optimisation).

### 9.1 Per-activity

```swift
struct ActivitySummary: Sendable {
    let activityID: UUID
    let sport: Sport
    let distanceMeters: Double?
    let movingTime: TimeInterval
    let averageHeartRateBPM: Double?
    let timeInZone: TimeInZone            // seconds per HR zone
    let load: TrainingLoad
}

struct TimeInZone: Sendable {
    let seconds: [Int: TimeInterval]      // zone number → seconds; zone 0 = below Z1
    var total: TimeInterval
    func fraction(of zone: Int) -> Double
}
```

Time in zone is integrated from `Activity.heartRate` using the same trapezoid segments and gap rule as the TRIMP calculator (one `HeartRateSegmentIterator` shared by both, so zone seconds and TRIMP always agree on what counts as "in the activity"). A sample straddling a zone boundary is split proportionally, not assigned whole.

> **Note (pending, not yet built):** `ActivitySummary`/`TimeInZone` should gain a pace/speed equivalent alongside the HR one — `Activity.speed` (added when the model gained device-recorded streams; see §2.2) is the raw stream to integrate the same way, once a pace/speed zone model exists to bucket it against. On the "computed on demand, cache is a later optimisation" line above: recomputing time-in-zone for e.g. 30 activities in a calendar view is not expected to be a real cost (trapezoidal integration over a few hundred–low-thousand samples per activity is sub-millisecond total), so if caching is ever needed it belongs at the app/view-model layer (keyed on activity ID, invalidated on data change), not inside `StatisticsCalculator` itself.


#### Step targets (MVP5-122)

`StepTargetResolver.resolve(_:on:athlete:raceTarget:raceTargetFraction:)` turns a template's intensities into numbers for one athlete on one date. It is a pure function; the caller stores the returned workout in the plan, so a workout sent to a watch does not move when zones are edited, and a re-plan (MVP5-123) resolves again.

Worked example: rest 50, max 190 bpm (Karvonen), threshold pace 4:00/km, race pace 4:00/km, phase fraction 0.98. A work step at `.heartRateZone(4)` becomes `.heartRateRange(162, 176)`; zone 4's pace range is 230.4...249.6 s/km (240 s/km times 1.0, bounds halfway to the zone 3 and zone 5 paces). The phase pace is 240 / 0.98 = 244.9 s/km, inside that range, so the `companionTarget` is `.pace` of 244.9 ±2 %. A fraction scales speed: 1.05 gives 228.6 s/km, which is a zone 5 pace, so the same step is reported as `paceOutsideZone(zone: 4, paceZone: 5)`: the phase asks for a different workout than this template. The step then keeps the zone's own pace as companion.

Rules: the primary `target` stays what the device alerts on and what `TRIMPPlanEstimator` and `WorkoutDurationEstimator` read; the resolved range has the zone's midpoint ratio, so they see the same zone as before. Warmup, recovery and cooldown steps get the zone's pace, never the phase pace. A work step with no target gets `.pace` from the fraction. Explicit pace, power, heart-rate range and RPE targets are kept. Only a `.pace` race target is turned into a pace; a missing race target, a heart-rate, effort or predicted target, no zone settings, and a zone with no bpm range (zone outside 1...5, or lactate threshold without a threshold heart rate) are reported in `unresolved` and leave the step as it was. The tolerances (zone bounds halfway between neighbouring zone paces, ±2 % around the phase pace) are fixed. Not done: the fitter does not yet use `paceOutsideZone` to reject a template, the generator calls it for every planned run (MVP5-145) and does not report `unresolved` (the proposal has no compromise case for it).

#### Polarized (80/20) intensity split

```swift
struct PolarizedIntensitySplit: Sendable {
    let lowSeconds: TimeInterval           // zone 0 + zones 1-2
    let moderateToHighSeconds: TimeInterval // zones 3-5
    var total: TimeInterval
    var lowFraction: Double
    var moderateToHighFraction: Double
}

extension TimeInZone {
    var polarizedSplit: PolarizedIntensitySplit
}
```

Collapses `TimeInZone`'s five HR zones into the two-zone model behind the "80/20" polarized-training guideline (Fitzgerald, *80/20 Running*/*80/20 Triathlon*): zone 0 and zones 1–2 (recovery/aerobic) count as low intensity, zones 3–5 (tempo/threshold/anaerobic) as moderate-to-high — this 1-2 vs. 3-5 split matches the zone grouping used in that source, confirmed rather than an arbitrary boundary. A `+` operator mirrors `TimeInZone`'s own, so a per-activity split rolls up into a weekly/period one the same way its source `TimeInZone` does (sum-then-split == split-then-sum). Exposed as a computed property on `TimeInZone` rather than a separate builder, since it needs no additional input.

### 9.2 Per-week

```swift
struct WeeklyStats: Identifiable, Sendable {
    let id: Date                          // week start in athlete timezone
    let weekStart: Date
    let isProjected: Bool                 // includes planned activities
    let bySport: [Sport: SportWeekStats]
    let totalDistanceMeters: Double
    let totalTime: TimeInterval
    let totalLoad: Double
    let timeInZone: TimeInZone
    let activityCount: Int
    let longestActivityTime: TimeInterval
    let longestActivityDistanceMeters: Double?
    let delta: WeeklyDelta?               // vs previous week, nil for first week
}

struct WeeklyDelta: Sendable {
    let distanceMeters: Double            // absolute change
    let distanceFraction: Double          // relative change, e.g. 0.12 = +12 %
    let time: TimeInterval
    let timeFraction: Double
    let load: Double
    let loadFraction: Double
}

struct StatisticsCalculator: Sendable {
    func summary(for activity: Activity, athlete: AthleteProfile) -> ActivitySummary
    func weeklyStats(activities: [Activity], plans: [PlannedActivity],
                     workouts: [StructuredWorkout], athlete: AthleteProfile,
                     asOf today: Date, weekStartsOn: Weekday) -> [WeeklyStats]
}
```

- Week boundary and first weekday come from `AthleteProfile` (add `weekStartsOn: Weekday`, default Monday), same timezone rule as daily bucketing so a Sunday-night run doesn't land in next week.
- Future weeks are projected from planned activities: distance/time from the workout steps via `PaceModel`, time in zone from the step targets. `isProjected` marks them, and a partial current week mixes actual and planned exactly like the daily series.
- **Pace forecasts (MVP2-35, MVP2-111).** Given a `PaceHistory`, the projection forecasts paces from the athlete's own earlier workouts instead of `PaceModel` alone (`StatisticsCalculator.projection(for:athlete:paceHistory:before:excluding:)`, and a `paceHistory:` argument on `periodStats`/`periodStatsSplit` so the totals agree with the per-workout figures):
  - `PaceHistory` holds, per activity with speed and heart-rate streams, the time and distance run in each heart-rate zone (zones as of the activity's date). For an activity linked to a plan it also lays the workout's steps over the recording (time steps by time, distance steps by the integrated speed, open steps share the remaining time) and records each step's kind, target zone, time and distance. `TrainingModel.refreshPaceHistory(in:)` builds it from the store, not just the loaded window.
  - `HistoricalPaceEstimator` matches earlier activities of the same sport family whose time-in-zone mix overlaps the plan's by at least half, weighted by overlap², duration similarity, recency (60-day half-life) and ×2/×3 for the same template/workout; the best 12 count. Only activities before the cutoff (the plan's date) are used, so a plan's own activity never informs what it expected.
  - Pace per zone: the matches' distance over time in the zone, shrunk towards the `PaceModel` pace (scaled by how much faster or slower the matches ran overall) by 300 s of pretend evidence, then made non-decreasing in speed with the zone (pool adjacent violators), so zone 1 is never forecast faster than zone 4.
  - Pace per step: earlier steps of the same kind and target zone, weighted by match weight and length similarity, shrunk towards the zone's pace — a zone-2 recovery jog between intervals is not forecast at steady zone-2 pace.
  - An `.open` step takes the **recency-weighted median** time (the weights `LinkedActivityRefinedEstimator` uses for TRIMP: a run's weight halves for every 60 days it is older than the newest run) the same step (same block/step position) took in earlier runs of the same workout, else of workouts from the same template; a run of the same workout that lasted less than 75% of the workout's fixed steps (everything but its open steps, whose length is what's being learned; a session cut short) is skipped, and when none of the workout's runs is usable the template's are, else `WorkoutDurationEstimator.defaultOpenStepDuration`.
  - Paces are moving paces at both levels: stretches slower than 0.5 m/s (stops) count towards neither. An open step's learned duration is elapsed time, stops included. Ages for the recency weight count from the newest usable activity, not the plan date, so a workout planned weeks ahead isn't forecast less confidently.
  - With no match and no open-step evidence the projection is exactly the `PaceModel` one. Each step keeps its target zone; only the duration of distance and open steps changes, and with it their time in that zone. Load estimates (`TRIMPPlanEstimator`) still use `WorkoutDurationEstimator`.
  - The calendar export uses the same forecast (`CalendarExportBuilder.paceHistory`).
- `WeeklyDelta.distanceFraction` is the "10 % rule" number; `PlanEvaluator` (§8.2) can add a `maxWeeklyDistanceIncrease` guardrail on it — it's a cruder signal than CTL ramp but runners recognise it.
- Rolling views (4-week averages, monthly, year-to-date) are derived from `[WeeklyStats]` in the app rather than being separate calculators.

### 9.3 Tests

- Zone splitting: a 10-minute sample pair that crosses Z2→Z3 halfway gives 300 s in each.
- Time in zone total equals moving time (minus gaps) for every activity.
- Week assignment at the boundary in a non-UTC timezone.
- Delta is `nil` on the first week and `fraction` is `nil`/`.inf`-guarded when the previous week is zero.

---

### 9.4 Calendar export (MVP2-100)

`TrainingModel.calendarExport(from:through:templates:asOf:)` returns a `CalendarExport`, a
day-by-day view of any period, past or future, for use outside the app (a season plan in a
spreadsheet, another analysis tool). `CalendarExport.jsonData()` writes it as pretty-printed JSON
with sorted keys, ISO 8601 timestamps and `yyyy-MM-dd` day strings in the athlete's time zone.
Missing values are written as `null` rather than left out, so every day and entry has the same keys.

```json
{
  "schemaVersion": 1, "generatedAt": "…", "timeZone": "Europe/Amsterdam",
  "firstDay": "2026-10-01", "lastDay": "2027-04-30",
  "days": [
    { "date": "2026-10-01",
      "metrics": { "load": 85, "ctl": 52.1, "atl": 61.3, "tsb": -7.4, "monotony": 1.2, "strain": 410,
                   "isProjected": false, "isWarmingUp": false },
      "activities": [
        { "status": "completed", "start": "…", "name": "Tempo 3 × 8 min", "sport": "running",
          "template": "Tempo Run", "intensity": "medium", "trimp": 85, "trimpSource": "heartRate",
          "durationSeconds": 3120, "distanceMeters": 9800,
          "plan": { "name": "Tempo 3 × 8 min", "template": "Tempo Run", "trimp": 90,
                    "trimpSource": "estimated", "durationSeconds": 3000, "distanceMeters": 9500 },
          "steps": [
            { "kind": "warmup", "block": 0, "repetition": 1, "goal": "time", "durationSeconds": 600,
              "distanceMeters": 1700,
              "target": { "type": "heartRateZone", "zone": 2, "rpe": null, "min": null, "max": null } } ] } ] } ]
}
```

`tsb` is the previous day's CTL minus the previous day's ATL (the form the athlete starts the day
with), so it isn't `ctl − atl` of the same row.

What's included (`CalendarExportBuilder`, a pure function):
- **Every calendar day** in the period, including empty ones.
- **Completed activities**, with their measured or exertion-based TRIMP, elapsed duration (pauses
  included, not moving time), distance and intensity. A recorded activity has no name of its own, so `name` is the name of the plan it
  fulfilled, or `null`.
- **A fulfilled plan** appears once, as `plan` on its activity (expected TRIMP, duration and
  distance next to the actual ones), not as a second entry.
- **Unfulfilled plans for today or later**, with expected TRIMP (the override, or the estimator),
  projected duration and distance, and intended intensity. A time-based workout's distance is
  forecast from `TrainingModel.paceHistory` (see "Pace forecasts" in §9), the same figure the app's
  detail sheet shows; the week view's planned cards show only the measure the workout defines.
  `trimpSource` says where each TRIMP came from: `heartRate`, `perceivedExertion`, `manual`,
  `estimated` or `override`. **Missed plans** (before today, never
  performed) are left out, as on the week view: they never became load. Only activities inside the
  period can fulfil a plan: a run just after the period's end that fulfilled the last day's plan
  doesn't, so that plan is left out as missed (or listed as planned, if it's today or later).
- **A completed activity with no usable load** (no calculator could score it, or a heart-rate
  recording that gave exactly zero, from too few samples or no zone settings in effect on that
  date) has `trimp` and `trimpSource` `null`, not a zero labelled `heartRate`.
- **Steps** (MVP2-102): every entry has a `steps` array, always present. A planned workout lists
  its steps with block repetitions expanded (6 × 400 m is twelve work and recovery steps), each
  with `kind` (`warmup`, `work`, `recovery`, `cooldown`), `block` (from 0), `repetition` (from 1),
  `goal` (`time`, `distance`, `open`), `durationSeconds`, `distanceMeters` (the goal, or projected
  from the pace model; `null` for a non-distance step when the athlete has no heart-rate zone
  settings) and its `target`. A completed activity carries the steps of the plan it
  fulfilled, i.e. what was intended; without a plan it's empty, as activities record no laps.
- **"Workout type"** is three fields: `sport`, the `template` a planned workout was built from, and
  the `intensity` category.
- **Templates** (MVP2-141): a planned entry built from a template also carries `templateID` and
  `parameterValues` (the values it was instantiated with, by parameter key; both `null` otherwise).
  The file's top-level `templates` array holds the full definition of each **custom** template a
  planned entry uses, once each, archived ones included (MVP2-142), sorted by name then id. Built-in
  templates are named by id only, since every app has them. A definition is written in the file's own
  vocabulary (`CalendarExport.Template`: parameters with `unit` `minutes`/`meters`/`count`, blocks with
  `repetitions` or `repetitionsParameter`, steps with `kind`, `goal` and a fixed value or a
  `…Parameter` key, and the same `target` as a step). Fields that don't apply are left out. A file
  without `templates` still reads, as empty (the schema version stays 1: adding fields doesn't bump it).
- **Metrics** per day: load, CTL, ATL, TSB, monotony, strain (`null` when undefined, e.g. a flat
  week), and the projected and warming-up flags.

The export reads the stores directly, so the model's loaded `activities`, `plans` and `metrics`
are untouched. It computes metrics fresh, starting `6 × ctlTimeConstantDays` (about eight months)
before the period. That's enough warm-up for CTL and ATL to match the app's cache-seeded series
to well within rounding, without reading the athlete's whole history. The cost is that about eight
months of activities, with their heart-rate samples, are read and scored on every export however
short the period. Not using the cache is deliberate: the export is then an independent
recomputation, which is how a cache seeding bug was found. The work runs off the main actor and
stops if the calling task is cancelled.

### 9.5 Calendar import (MVP2-103)

`CalendarExport.decode(from:)` reads an export file back, and `TrainingModel.importCalendar(_:asOf:)`
adds its planned workouts as plans. `calendarImportPreview(_:)` reports what an import would do
without changing anything. The pure `CalendarImportPlanner` decides, so it is tested without stores.

What is imported:
- **Planned entries only.** Each becomes a `PlannedActivity` on its day, read in the athlete's own
  time zone so the day lands where it does in the app. The workout is rebuilt from the template the
  entry names (MVP2-141) when the library has it (built-in, or custom) or the file defines it:
  instantiated with the entry's `parameterValues`, so it keeps its template link and can be
  re-opened with the template's parameters. Otherwise (an older file, a template that is neither in
  the library nor the file, an unreadable definition) it is rebuilt from the entry's `steps`: steps
  of one `block` form a block, repeated as often as the block's highest `repetition`, with no
  template link. A step kind or goal this version doesn't know rejects such an entry.
- **Templates in the file** are added to the library (`TrainingModel.templates`, saved to the
  template store) only when a plan that is added uses them. A template equal to one the library has
  (same sport, parameters and blocks; the name, id and archived state don't count) isn't added: the
  workouts link to the existing one, a live one in preference to an archived one. One whose id the
  library holds with a different definition is added as a copy with a new id, so neither changes.
  Two equal templates in one file become one. Without a template store nothing is added, and the
  entries fall back to their steps.
- **The file isn't trusted.** A template definition is rejected (counted, its workouts keep their
  steps) when a fixed repeat count isn't in 1...100, a fixed time or distance isn't positive, two
  parameters share a key, a default lies outside its range, or it refers to an undeclared parameter.
  An entry's parameter value that isn't declared, isn't a number or is outside the parameter's range
  is dropped, so the parameter keeps its default; a workout that is still absurd (a parameter with
  no range driving a huge repeat count) is rebuilt from the entry's steps instead.
- **Entries before today are skipped and counted.** Such a plan would only show as missed and never
  counts as load; the export leaves missed plans out for the same reason.
- **Completed entries become placeholder activities (MVP2-107).** The file has no heart-rate data,
  so a placeholder has a start, a duration, a distance and the file's TRIMP as
  `Activity.importedLoad`, which `ImportedLoadCalculator` scores (method `.manual`, confidence 1)
  between the heart-rate and the duration/RPE estimators. `Activity.isCalendarImport` marks it (and
  `ActivityListItem.isCalendarImport`), so the app can say the activity has no heart rate. Both fields
  are optional in the stored JSON, so no migration is needed. A completed entry with no start or
  no positive duration is rejected (`.invalidActivity`).
  - **Source id.** The export carries a HealthKit workout's id as `sourceID` (additive, within schema
    version 1). A placeholder with one is stored under `.healthKit(id)` with that id, so
    HealthKit's own import finds it by source and replaces it in place. Without one (a file from
    another tool) it is `.manual`, with a new id.
  - **Not repeated.** An entry is skipped (`activitiesSkippedDuplicates`) when its source is stored,
    or when a stored activity is the same workout by `PlaceholderActivityMatching`: the same sport
    family, a start within five minutes and a duration within a fifth (at least two minutes).
  - **HealthKit replaces them.** When an import brings a new activity that matches a placeholder this
    way, the placeholder is removed (without a tombstone, so a workout HealthKit reports still
    imports), its plan is released and the plan is matched again to the real workout.
  - **The import anchor isn't touched.** The placeholders are applied through the same path as an
    import (`applyImport`, queued with it) without saving an anchor, so HealthKit still fetches
    everything it hasn't seen.
- **Daily metrics are never imported.** The model recomputes CTL, ATL, TSB, monotony and strain from
  the plans and activities.
- **Expected TRIMP** becomes the plan's load override when the entry's `trimpSource` is `override`,
  or when the TRIMP differs from the estimator's value for the rebuilt steps by more than 0.5, so a
  load edited outside the app survives. An untouched estimate is left to be recomputed.

Duplicates: a plan is skipped when the app already has one on the same day for an equal workout
(name, sport and blocks, whatever template it was built from), so importing a file twice adds
nothing, and an older file imported over template-linked plans adds nothing either. The same workout
twice on one day is allowed: only the occurrences beyond those already stored are added. A new workout
equal to one in the library isn't repeated; the plan refers to the existing one. The exception is a
file entry with a template link: it reuses an equal workout only if that has the same template and
values, so a plan isn't tied to a workout without the link it should have.

An entry without `steps` (a file written before MVP2-102) is rejected, since no workout can be
rebuilt. A file with a newer `schemaVersion` than the app understands, or one that isn't an export,
is refused with a `CalendarImportError`. The result is a `CalendarImportReport`: added, skipped as
duplicates, skipped as past, completed skipped, and rejected entries with a reason, plus the
templates added, linked to an existing one, added as copies and rejected (unreadable, or no store).

Templates are saved first, then the new workouts, then the plans that use them, so a failure partway
leaves at worst unused library entries. Afterwards the model reloads its loaded range and reconciles the plans with the activities
loaded. The file's days are loaded only when nothing was loaded yet: widening the range for a long
file would load and recompute a whole season of activities, and the week view loads other weeks
when they are shown. The plans aren't scheduled in WorkoutKit: that stays
with the app's scheduler (MVP2-55).

## 10. Periodisation — macro, meso, micro cycles (Core, MVP 1)

Cycles are the calendar structure that plans and statistics hang off, and they ship in MVP 1: the user creates them (by hand or from a template), plans activities inside them, and reads statistics per cycle. Nothing in the load model depends on them, but the evaluator does, and MVP 2's generator builds on the same `CycleLayoutBuilder` rather than introducing anything new.

### 10.1 Model

```swift
enum CycleLevel: Sendable, Codable { case macro, meso, micro }

/// What the athlete is working on: a named, paradigm-defined value (MVP5-113). The built-ins
/// are static constants (`.base`, `.build`, `.peak`, `.taper`, `.race`, `.recovery`, `.transition`);
/// a paradigm adds its own, e.g. `CyclePhase("structural")`. Encodes as its `id` string; the old
/// enum payload (`{"build":{}}`) still decodes.
struct CyclePhase: Sendable, Hashable, Codable, ExpressibleByStringLiteral { let id: String }

/// How hard a micro is meant to be, independent of its phase. Rules read this, not the phase name.
/// `race` is no longer produced by a layout (MVP5-111); it stays so stored micros decode.
enum MicroLoadRole: String, Sendable, Codable { case build, recovery, taper, race }

struct TrainingCycle: Identifiable, Sendable, Codable {
    let id: UUID
    var level: CycleLevel
    var phase: CyclePhase
    var loadRole: MicroLoadRole?          // micros only; derived from a legacy phase when absent
    var name: String                      // "Ultra prep 2027", "Meso 3", "Week 11"
    var dateRange: ClosedRange<Date>      // day-granular, athlete timezone
    var parentID: UUID?                   // micro → meso → macro
    var targetRaceID: UUID?               // macro/meso pointing at a Race
}
```

Rules enforced by `CycleStore` on insert: a child range must lie inside its parent, siblings don't overlap, and micros are not required to be 7 days (a 10-day micro is legitimate). Gaps are allowed — untracked time is just no cycle.

### 10.2 Templates

A template describes a repeating pattern so the user (or the generator) doesn't lay out every week by hand:

```swift
struct MesocycleTemplate: Sendable, Codable {
    var name: String                      // "3:1"
    var microRoles: [MicroLoadRole]       // [.build, .build, .build, .recovery]
    var microLengthDays: Int = 7
    var recoveryLoadFraction: Double = 0.6 // recovery micro target relative to prior micro peak
    var buildLoadStep: Double = 0.08       // load increase per build micro, fractional
}

struct CycleLayoutBuilder: Sendable {
    func layout(from start: Date, to race: Race, macro: MacroTemplate,
                meso: MesocycleTemplate, athlete: AthleteProfile) -> [TrainingCycle]
}
```

`CycleLayoutBuilder` works backwards from the race: every micro takes its block's phase, and its load role comes from the pattern — the micro with race day is `.taper` (there is no race role in a layout), taper-block micros are `.taper`, and the rest cycle `microRoles`. It lays out the race micro, taper micro(s), then fills toward the start with repeating meso templates, trimming the first meso if the total doesn't divide. Output is just `[TrainingCycle]`; the user can edit the result. Built-in templates: `3:1`, `2:1`, and `linear` (no recovery micro, for short blocks).

In MVP 1 the builder is driven by the user ("lay out a 3:1 block from today to this race"); in MVP 2 the generator calls it and then fills the micros. A `MacroTemplate` is the ordered list of meso phases (`[.base, .base, .build, .build, .peak, .taper]`) with meso lengths; `Race` in MVP 1 is just `id`, `name`, `date`, `priority` (`RacePriority`: `.primary`/`.secondary`/`.tertiary`, acted on by `KeyRaceLayout`, MVP5-111) — enough to anchor a layout and the race-day TSB rule.

The triphasic phase lengths (6-week structural and specific blocks, a 1-week taper, a base of at least 6 weeks), how they flex with the lead time and how they sit on 7-, 10- and 14-day micros are described in [triphasic-design.md](triphasic-design.md) §3 (MVP5-100); the layout itself is not built for triphasic yet.

### 10.3 Statistics over cycles

Weekly stats generalise to any period, so `WeeklyStats` becomes a special case:

```swift
struct PeriodStats: Sendable {
    let range: ClosedRange<Date>
    let isProjected: Bool
    let bySport: [Sport: SportPeriodStats]
    let totalDistanceMeters: Double
    let totalTime: TimeInterval
    let totalLoad: Double
    let timeInZone: TimeInZone
    let activityCount: Int
    let longestActivityTime: TimeInterval
    let longestActivityDistanceMeters: Double?
    let delta: PeriodDelta?               // vs previous period of the same level
}

struct CycleStats: Identifiable, Sendable {
    let id: UUID                          // cycle id
    let cycle: TrainingCycle
    let period: PeriodStats
    let children: [CycleStats]            // meso → its micros, macro → its mesos
    let fitness: CycleFitness
}

struct CycleFitness: Sendable {
    let ctlStart: Double
    let ctlEnd: Double
    var ctlGain: Double { ctlEnd - ctlStart }
    let peakATL: Double
    let peakMonotony: Double
    let peakStrain: Double
    let minTSB: Double
    let loadVsPreviousSibling: Double?    // this micro's load / previous micro's load
}

extension StatisticsCalculator {
    func cycleStats(for cycles: [TrainingCycle], metrics: [FitnessMetrics],
                    activities: [Activity], plans: [PlannedActivity],
                    workouts: [StructuredWorkout], athlete: AthleteProfile,
                    asOf today: Date) -> [CycleStats]
}
```

`WeeklyStats` is retained as a typealias-style convenience over `PeriodStats` for calendar weeks that aren't part of any cycle, so the weekly view works before the user has set up periodisation.

The delta for a cycle compares against the previous sibling at the same level and, for micros, also exposes "vs last micro of the same phase" — a recovery week is meant to be lower than the build week before it, so the interesting comparison is recovery-to-recovery and build-to-build.

### 10.4 Evaluator rules that need cycles

No cycle-based guardrail remains. The build-progression rule (mean daily load of a build micro against the previous one) was replaced by the longest-run rule of §8.2 (MVP5-116), which reads planned runs, not cycles. `PlanEvaluator.evaluate` still takes `cycles: [TrainingCycle]`, but only the micro-based paradigm rules of §8.2 (hard sessions per micro, intensity distribution) read it.

---

## 11. LLM tool layer (`TrainingTools`, MVP 3)

Everything above is exposed to a language model as a set of typed tools, so the MVP 3 "coach" — or an ad-hoc chat in the app — can read the athlete's data, run what-if simulations, and propose plan changes. This is a separate MVP from the plan generator (MVP 2): the generator ships first as a fully deterministic, heuristic-driven loop with no model dependency, and the coach layer is an optional, later addition on top of it. The design principle: **the LLM never computes fitness numbers, it calls tools that do**, and every write goes through a sandbox that the user commits explicitly.

### 11.1 Provider-neutral core

```swift
protocol TrainingTool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable
    static var name: String { get }
    static var description: String { get }      // written for the model, not for docs
    static var isMutating: Bool { get }
    func run(_ input: Input, context: ToolContext) async throws -> Output
}

struct ToolContext: Sendable {
    let stores: StoreSet                        // Activity/Plan/Workout/Cycle/Athlete
    let sandbox: PlanSandbox                    // mutations land here, not in the stores
    let today: Date
    let athlete: AthleteProfile
}

struct ToolRegistry: Sendable {
    func schemas() -> [ToolSchema]              // name, description, JSON Schema for Input
    func dispatch(name: String, argumentsJSON: Data, context: ToolContext) async throws -> Data
}
```

`ToolSchema` is generated from `Input` via a small `JSONSchemaEncoder` (reflection over `Codable`, with a `@ToolDescription("...")` property wrapper for per-field hints). One source of truth; the Anthropic and Foundation Models adapters both render from it.

### 11.2 Tool set for MVP 3

Read-only:

| Tool | Returns |
|---|---|
| `get_athlete_profile` | HR rest/max, zones, pace model, week start |
| `list_activities(range, sport?)` | `ActivitySummary` list (no raw HR samples — too large, no value to the model) |
| `get_fitness_metrics(range, resolution: daily\|weekly)` | `FitnessMetrics` series, projected flag included |
| `get_period_stats(range)` / `get_cycle_stats(cycleID?)` | `PeriodStats` / nested `CycleStats` |
| `list_workouts(sport?)` | Library, step structure summarised |
| `list_planned_activities(range)` | Plans with expected load |
| `list_cycles(range)` | Cycle tree |
| `list_races` | Upcoming races/goals |
| `evaluate_plan(scope: committed\|sandbox)` | `PlanEvaluation` findings, grouped by rule |

Mutating (sandbox only):

| Tool | Effect |
|---|---|
| `add_planned_activity(workoutID, date)` / `move_planned_activity` / `remove_planned_activity` | Edits the sandbox plan set |
| `create_workout(StructuredWorkout)` | Adds to sandbox library |
| `layout_cycles(raceID, mesoTemplate)` | Runs `CycleLayoutBuilder` into the sandbox |
| `simulate` | Recomputes series + stats + evaluation over the sandbox; the model's what-if loop |
| `diff_sandbox` | Human-readable summary of committed → sandbox changes, for the confirmation UI |

`commit_sandbox` is deliberately **not** a tool. The app shows the diff and the user commits; the model can only propose.

### 11.3 Sandbox

```swift
actor PlanSandbox {
    init(snapshotOf stores: StoreSet) async throws
    var plans: [PlannedActivity]
    var workouts: [StructuredWorkout]
    var cycles: [TrainingCycle]
    func simulate(engine: SeriesEngine, evaluator: PlanEvaluator) async -> SimulationResult
    func diff() -> SandboxDiff
    func commit(to stores: StoreSet) async throws
    func reset()
}
```

The sandbox is also what a non-LLM UI uses for "try this change and see the curve", so it earns its keep regardless of the model.

### 11.4 Adapters

- **`TrainingToolsAnthropic`** — renders `ToolSchema` into the Messages API `tools` array, runs the tool-use loop (`tool_use` → dispatch → `tool_result` → continue) with a bounded iteration count and per-call timeouts. Model choice per task: Haiku for tool-heavy summarising, Sonnet/Opus for the actual planning turn. Keep prompt state outside the package — it only owns the tool loop and a `CoachSystemPrompt` builder that injects athlete context (zones, guardrails, cycle template) so the model doesn't have to fetch them every turn.
- **`TrainingToolsFoundationModels`** — same registry mapped onto Apple's on-device `FoundationModels` `Tool` protocol and `@Generable` types. iOS 26+/macOS 26+ only, gated with `#if canImport(FoundationModels)`. Good for quick, offline "how was this week" questions; too small a model for multi-week planning.
- Both adapters share `ToolContext`; the app decides which provider to use per request.

### 11.5 Guardrails on the guardrails

- Tool outputs are capped (max rows, summarised HR) so a season of data doesn't blow the context.
- Every mutating tool re-runs `PlanEvaluator` and returns the findings in its output, so the model sees the consequence of each edit immediately rather than having to remember to call `evaluate_plan`.
- `ToolContext.today` is injected, so the same conversation is replayable in tests with a fixed date.
- Log every dispatch with `os.Logger` category `Tools`, arguments redacted to IDs.

Tests: schema round-trips for every tool input, a scripted fake provider that exercises the loop end to end, and a "runaway model" test that asserts the iteration bound stops a tool loop that never terminates.

---

## 12. Roadmap seams

| MVP | Adds | Where it plugs in |
|---|---|---|
| 2 — plan generator | `Race`/`Goal` model, `SessionType` tag on `StructuredWorkout` (§2.4), `PlanPreferences` (§8.1: training days, per-day sport/surface/session-type, starting per-session and weekly volume, session caps, weekly ramp), `PlanGenerator` that reuses `CycleLayoutBuilder` (§10.2, already in MVP 1) and then fills each micro with `[PlannedActivity]` from the library, iterated against `PlanEvaluator` via a fixed set of heuristic adjustments (§8.2) — no LLM involved | Emits plain `PlannedActivity` values through `PlanStore`; runs `DailyLoadSeries` with a hypothetical `today` to preview outcomes; `PlanEvaluator` (§8.2) is the accept/reject gate, `PlanPreferences` is what the proposal is seeded from |
| 3 — LLM coach | `TrainingTools` typed tool layer (§11) driving the same `PlanGenerator`/`PlanEvaluator` conversationally through a `PlanSandbox`; Anthropic and on-device Foundation Models adapters | Reuses MVP 2's `PlanGenerator`/`PlanEvaluator`/`PlanStore` seams unchanged; adds the sandbox and tool dispatch on top |
| 4 — calibration | `ResidualStore` of (expected, actual) pairs from `PlanReconciler`; `CalibratedPlanEstimator` scaling per sport/zone; optional tuning of `TRIMPCoefficients` and `LoadModelParameters` | Swaps the `PlannedLoadEstimator` implementation; nothing upstream changes |
| Garmin/COROS | `TrainingFIT` — FIT workout export from `StructuredWorkout`, FIT/TCX activity import | Second `ActivityImporting` implementation; second exporter next to `WorkoutKitBridge` |

Open questions to settle before coding:
1. Store CTL/ATL in the persistence layer, or always derive? (Recommend derive; only persist loads.)
2. Should `Activity` for non-HR sports (strength) be excluded from the series or scored by RPE? Affects how many `LoadCalculator`s exist on day one.
3. Cross-device: is CloudKit via SwiftData acceptable, or do you want the Mac to read a shared container some other way?
