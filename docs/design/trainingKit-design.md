# trainingKit — Package Design (MVP 1)

Swift package for iOS 26+, watchOS 26+, macOS 26+. Library only, no UI.

Scope of MVP 1:
- Import completed activities (HealthKit first, file import later) and compute a training load (HR-TRIMP) per activity.
- Maintain a library of structured workouts, synced to Apple WorkoutKit where the platform allows.
- Let the user plan activities (structured workout + date) and estimate their expected load.
- Let the user lay out training cycles (macro / meso / micro, e.g. a 3:1 pattern with a recovery week) manually or from a template, and attach plans and statistics to them.
- Produce one continuous daily fitness series — measured in the past, projected in the future — with CTL / ATL / TSB / monotony / strain per day, plus period and cycle statistics.
- Evaluate the committed plan against injury-risk and progress guardrails (read-only in MVP 1; the generator that acts on the findings is MVP 2).

Designed so MVP 2 (plan assistant) and MVP 3 (calibration from planned-vs-actual residuals) slot in without reshaping the core.

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
    var paceModel: PaceModel                        // used to turn distance steps into time
    var timeZone: TimeZone                          // daily bucketing boundary
    var weekStartsOn: Weekday                       // weekly stats boundary, default .monday
    var heartRateZoneHistory: [HeartRateZoneSettings] // resting/max HR + zone method, dated so
                                                       // recomputing an old activity's load uses the
                                                       // settings effective on its date, not today's
}
```

`HeartRateZoneModel` derives `deltaHRRatio(for bpm:)` from the profile and maps HR zones ↔ ratios so a workout step targeting "Zone 3" can be turned into a TRIMP intensity.

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
    var source: ActivitySource        // .healthKit(uuid), .fitFile(url), .manual
    var sport: Sport
    var start: Date
    var duration: TimeInterval
    var distanceMeters: Double?
    var heartRate: [HeartRateSample]  // may be empty
    var linkedPlanID: UUID?           // reconciliation with a PlannedActivity
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
    var confidence: Double            // 1.0 measured, < 1 for estimates; used by MVP 3
}

protocol LoadCalculator: Sendable {
    func load(for activity: Activity, athlete: AthleteProfile) throws(LoadError) -> TrainingLoad
}
```

`ExponentialTRIMPCalculator` is the MVP implementation:

- Integrates Banister's exponential TRIMP over the HR stream, trapezoidally between consecutive samples.
- Coefficients `(0.64, 1.92)` male, `(0.86, 1.67)` female, held in a `TRIMPCoefficients` value so MVP 3 can tune them.
- Gaps > 60 s between samples are not integrated (treated as a pause), configurable.
- Throws `LoadError.noHeartRateData` rather than returning 0, so callers can fall back to `DurationRPECalculator` (duration × RPE) for activities without HR.

### 2.4 Structured workouts (the library)

```swift
struct StructuredWorkout: Identifiable, Sendable, Codable {
    let id: UUID
    var name: String
    var sport: Sport
    var blocks: [WorkoutBlock]
    var workoutKitID: UUID?           // identity of the synced WorkoutKit plan, nil if unsynced
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
}
```

A plan is just workout + date; everything else is derived. Keeping it minimal is what lets MVP 2 generate plans as plain data.

### 2.6 Expected load estimation

```swift
protocol PlannedLoadEstimator: Sendable {
    func estimatedLoad(for workout: StructuredWorkout, athlete: AthleteProfile) -> TrainingLoad
}
```

`TRIMPPlanEstimator` walks the steps: each step's duration comes from its goal (`.time` direct, `.distance` via `PaceModel` at the step's target intensity, `.open` via default), each step's intensity comes from `IntensityTarget` → `deltaHRRatio` (zone midpoint), and the same Banister formula is applied per step. Result is a `TrainingLoad` with `method: .estimatedFromPlan` and `confidence < 1`. MVP 3 replaces this with a calibrated estimator that scales by observed residuals; the protocol boundary is the seam.

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

Core defines the storage contract; `TrainingPersistence` implements it with SwiftData (+ CloudKit so the Mac and Watch see what the phone imported).

```swift
protocol ActivityStore: Sendable {
    func activities(in range: ClosedRange<Date>) async throws -> [Activity]
    func upsert(_ activities: [Activity]) async throws
    func activity(sourceID: String) async throws -> Activity?   // dedupe on re-import
}

protocol PlanStore: Sendable { ... }
protocol WorkoutLibraryStore: Sendable { ... }
protocol CycleStore: Sendable { ... }       // enforces nesting/overlap rules on insert
protocol AthleteStore: Sendable { ... }
```

An `InMemoryStore` implementing all five ships in Core for tests and previews.

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
- `HealthKitAthleteReader` supplies resting HR (latest `restingHeartRate` sample) and `biologicalSex()` to pre-fill `AthleteProfile`. HRmax is never read from HealthKit; default to Tanaka (`208 − 0.7 × age`) from `dateOfBirth` and let the user override.

Requested authorisations: read `workoutType`, `heartRate`, `restingHeartRate`, `dateOfBirth`, `biologicalSex`. No write scopes in MVP 1.

### 5.2 `TrainingWorkoutKit`

```swift
struct WorkoutKitBridge {
    func customWorkout(from workout: StructuredWorkout) throws -> CustomWorkout
    func structuredWorkout(from plan: WorkoutPlan) throws -> StructuredWorkout
    func sync(_ workout: StructuredWorkout) async throws -> UUID       // returns WorkoutKit plan id
    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout) async throws
}
```

- Mapping is mechanical: `WorkoutBlock` ↔ `IntervalBlock`, `WorkoutStep` ↔ `IntervalStep`, `StepGoal` ↔ `WorkoutGoal`, `IntensityTarget` ↔ `WorkoutAlert`.
- Sync is one-directional in MVP 1: library → WorkoutKit. `StructuredWorkout.workoutKitID` records the link so re-syncs update rather than duplicate.
- Scheduling a `PlannedActivity` uses `WorkoutPlan`'s schedule API; WorkoutKit only shows ±7 days on the Watch, so scheduling is done lazily for plans within that window rather than for the whole season.
- Completed scheduled workouts can be queried back from WorkoutKit (date + completed flag, no health data). That's a cheap first signal for reconciliation before the HealthKit import lands.

### 5.3 Reconciliation (`TrainingCore`)

`PlanReconciler` links a completed `Activity` to a `PlannedActivity` on the same day with the same sport; closest duration wins if there are several. Sets `PlannedActivity.completedActivityID` and `Activity.linkedPlanID`. In MVP 1 this only affects the merge rule (today's actual beats today's estimate); in MVP 3 the `(expected, actual)` pairs it produces are the training data for calibration.

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
    Planning/         PlannedActivity, PlannedLoadEstimator, TRIMPPlanEstimator, PlanReconciler
    Series/           DayLoad, DailyLoadSeries, FitnessMetrics, FitnessMetricsCalculator,
                      LoadModelParameters
    Evaluation/       PlanEvaluator, PlanEvaluation, PlanFinding, PlanGuardrails
    Statistics/       ActivitySummary, TimeInZone, PeriodStats, PeriodDelta, WeeklyStats,
                      CycleStats, CycleFitness, StatisticsCalculator, HeartRateSegmentIterator
    Cycles/           TrainingCycle, CycleLevel, CyclePhase, MesocycleTemplate,
                      MacroTemplate, CycleLayoutBuilder
    Store/            ActivityStore, PlanStore, WorkoutLibraryStore, CycleStore, AthleteStore,
                      InMemoryStore
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

## 8. Plan evaluation (guardrails for MVP 2, defined in Core now)

The assistant in MVP 2 doesn't just emit a plan — it proposes one, runs it through the series engine, and checks the *projected* metrics against injury-risk and progress rules before accepting it. Because the evaluation is pure functions over `[FitnessMetrics]`, it belongs in `TrainingCore` and can ship in MVP 1 as a read-only "how does my current plan look" check.

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
    var maxCTLRampPerWeek: Double = 6          // CTL points gained per 7 days
    var maxATLtoCTLRatio: Double = 1.4         // acute:chronic analogue
    var minATLtoCTLRatio: Double = 0.7         // below this = detraining, not risk
    var maxMonotony: Double = 2.0
    var maxStrainPercentile: Double = 0.95     // relative to athlete's own trailing 12 weeks
    var minTSBOnRaceDay: Double = 5
    var maxTSBOnRaceDay: Double = 25
    var minCTLGainPerMeso: Double = 2          // "is there progress" over a build/base meso
    var maxMicrosWithoutRecovery: Int = 3      // e.g. 3:1 pattern
}

struct PlanEvaluator: Sendable {
    func evaluate(_ metrics: [FitnessMetrics], races: [Race],
                  guardrails: PlanGuardrails) -> PlanEvaluation
}
```

Rules, all computed from the projected series:

| Rule | Signal | Why |
|---|---|---|
| CTL ramp | CTL[d] − CTL[d−7] | Fitness climbing too fast is the classic overuse setup; fellrnr and Coggan both flag ~5–8/week as the ceiling for most runners |
| ATL/CTL ratio | ATL[d] / CTL[d] | Acute:chronic workload ratio analogue; > ~1.4–1.5 is the danger band, < ~0.7 means the plan is losing fitness |
| Monotony | 7-day mean / stdev | > 2.0 means the week has no easy/hard contrast, even at moderate volume |
| Strain | weekly load × monotony | Absolute thresholds don't transfer across athletes in TRIMP units, so compare against the athlete's own trailing distribution |
| Race-day TSB | TSB on `Race.date` | Taper landed: positive but not so high that fitness was lost |
| Progress | CTL at meso end − CTL at meso start | Guards against a "safe" plan that's actually flat (cycle-aware rules in §10.4) |

Guardrail values are `Codable` and user-editable; MVP 3 can tune them from observed outcomes (e.g. the athlete who tolerates a 1.5 ratio without issue).

The MVP 2 generator loop is then: propose → `DailyLoadSeries` → `FitnessMetricsCalculator` → `PlanEvaluator` → adjust (drop a session, swap hard for easy, insert a down-week) → repeat until acceptable. Whether the "adjust" step is heuristic or a Claude API call, the evaluator is what keeps it honest.

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
- `WeeklyDelta.distanceFraction` is the "10 % rule" number; `PlanEvaluator` (§8) can add a `maxWeeklyDistanceIncrease` guardrail on it — it's a cruder signal than CTL ramp but runners recognise it.
- Rolling views (4-week averages, monthly, year-to-date) are derived from `[WeeklyStats]` in the app rather than being separate calculators.

### 9.3 Tests

- Zone splitting: a 10-minute sample pair that crosses Z2→Z3 halfway gives 300 s in each.
- Time in zone total equals moving time (minus gaps) for every activity.
- Week assignment at the boundary in a non-UTC timezone.
- Delta is `nil` on the first week and `fraction` is `nil`/`.inf`-guarded when the previous week is zero.

---

## 10. Periodisation — macro, meso, micro cycles (Core, MVP 1)

Cycles are the calendar structure that plans and statistics hang off, and they ship in MVP 1: the user creates them (by hand or from a template), plans activities inside them, and reads statistics per cycle. Nothing in the load model depends on them, but the evaluator does, and MVP 2's generator builds on the same `CycleLayoutBuilder` rather than introducing anything new.

### 10.1 Model

```swift
enum CycleLevel: Sendable, Codable { case macro, meso, micro }

enum CyclePhase: Sendable, Codable {
    case base, build, peak, taper, race, recovery, transition
}

struct TrainingCycle: Identifiable, Sendable, Codable {
    let id: UUID
    var level: CycleLevel
    var phase: CyclePhase
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
    var microPhases: [CyclePhase]         // [.build, .build, .build, .recovery]
    var microLengthDays: Int = 7
    var recoveryLoadFraction: Double = 0.6 // recovery micro target relative to prior micro peak
    var buildLoadStep: Double = 0.08       // load increase per build micro, fractional
}

struct CycleLayoutBuilder: Sendable {
    func layout(from start: Date, to race: Race, macro: MacroTemplate,
                meso: MesocycleTemplate, athlete: AthleteProfile) -> [TrainingCycle]
}
```

`CycleLayoutBuilder` works backwards from the race: race micro, taper micro(s), then fills toward the start with repeating meso templates, trimming the first meso if the total doesn't divide. Output is just `[TrainingCycle]`; the user can edit the result. Built-in templates: `3:1`, `2:1`, and `linear` (no recovery micro, for short blocks).

In MVP 1 the builder is driven by the user ("lay out a 3:1 block from today to this race"); in MVP 2 the generator calls it and then fills the micros. A `MacroTemplate` is the ordered list of meso phases (`[.base, .base, .build, .build, .peak, .taper]`) with meso lengths; `Race` in MVP 1 is just `id`, `name`, `date`, `priority` — enough to anchor a layout and the race-day TSB rule.

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

Added to `PlanGuardrails` (§8):

| Rule | Signal | Check |
|---|---|---|
| Recovery micro actually recovers | recovery micro load / previous micro load | ≤ `recoveryLoadFraction` (default 0.6–0.7) |
| Build progression | build micro load vs previous build micro | between 0 % and ~+10 % |
| Meso progress | `CycleFitness.ctlGain` for a build/base meso | ≥ `minCTLGainPerMeso` |
| Taper shape | CTL drop across taper micro(s) | small (≤ ~10 %) while TSB rises into the race window |
| Consecutive load | number of micros since the last recovery-phase micro | ≤ template length, i.e. "you've gone 5 weeks without a rest week" |

`PlanEvaluator.evaluate` gains a `cycles: [TrainingCycle]` parameter; without cycles it falls back to the cycle-free rules from §8.

---

## 11. LLM tool layer (`TrainingTools`)

Everything above is exposed to a language model as a set of typed tools, so the MVP 2 "coach" — or an ad-hoc chat in the app — can read the athlete's data, run what-if simulations, and propose plan changes. The design principle: **the LLM never computes fitness numbers, it calls tools that do**, and every write goes through a sandbox that the user commits explicitly.

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

### 11.2 Tool set for MVP 2

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
| 2 — plan assistant | `Race`/`Goal` model, `PlanGenerator` that reuses `CycleLayoutBuilder` (§10.2, already in MVP 1) and then fills each micro with `[PlannedActivity]` from the library, iterated against `PlanEvaluator`; the coach layer is an LLM driving the §11 tools inside a `PlanSandbox` | Emits plain `PlannedActivity` values through `PlanStore`; runs `DailyLoadSeries` with a hypothetical `today` to preview outcomes; `PlanEvaluator` (§8) is the accept/reject gate |
| 3 — calibration | `ResidualStore` of (expected, actual) pairs from `PlanReconciler`; `CalibratedPlanEstimator` scaling per sport/zone; optional tuning of `TRIMPCoefficients` and `LoadModelParameters` | Swaps the `PlannedLoadEstimator` implementation; nothing upstream changes |
| Garmin/COROS | `TrainingFIT` — FIT workout export from `StructuredWorkout`, FIT/TCX activity import | Second `ActivityImporting` implementation; second exporter next to `WorkoutKitBridge` |

Open questions to settle before coding:
1. Store CTL/ATL in the persistence layer, or always derive? (Recommend derive; only persist loads.)
2. Should `Activity` for non-HR sports (strength) be excluded from the series or scored by RPE? Affects how many `LoadCalculator`s exist on day one.
3. Cross-device: is CloudKit via SwiftData acceptable, or do you want the Mac to read a shared container some other way?
