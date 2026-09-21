# Intensity Classification (MVP2-43)

Status: phases 1–3 implemented in TrainingCore (`Sources/TrainingCore/Intensity/`); phases 4–5 (pace/bout detection,
app display) and real-data tuning outstanding.

## 1. Goal

Give every planned and performed activity an intensity category:

| Category | Typical sessions |
|---|---|
| `veryLow` | recovery runs |
| `low` | easy runs, long runs |
| `medium` | tempo, fartlek, medium-intensity intervals, long runs with a fast finish |
| `high` | interval sessions, hill repeats, races |

Planned and performed values must be directly comparable (same enum, same rules), and the result feeds
card colouring (revives the canceled MVP2-9), the week stats, and later MVP5-5 (plan generator picks
intensity per `CyclePhase`).

## 2. Why the obvious signals fail

| Signal | Failure |
|---|---|
| TRIMP | Volume-weighted: a 2 h easy long run out-scores a 5×1 km interval session. |
| Max zone | Spike-sensitive: 20 s in Z3 turns an easy run into "medium". Intervals also spend most of their time in Z1–Z2. |
| Mean zone | Averages away intervals (work + recovery ≈ Z2). |
| Raw per-step zone (performed) | HR lags 20–40 s on the way up and longer on the way down: the Z5 peak of a short rep lands in the *following* recovery step, and recovery never reaches Z1–2 before the next rep. |
| Pace alone | Responds instantly (good for finding bouts) but hills break the pace↔effort relation (hill sprints look slow). |

## 3. What the data actually gives us (verified in the code)

- `Activity` has **no steps**. It carries HR samples, speed samples, and only *summary* elevation
  (`ElevationStats`: gain/loss/min/max) and cadence. No altitude stream, so grade-adjusted pace is not possible today.
- `HealthKitActivityImporter` imports the `HKWorkout` and its **heart-rate series only**. It reads no
  `HKWorkoutActivity`/`HKWorkoutEvent` (segments/laps), and it **does not populate `Activity.speed`** at all
  (no `SpeedSample` is created anywhere in `TrainingHealthKit`).
- Planned side is rich: `StructuredWorkout` → `WorkoutBlock` → `WorkoutStep` (`kind`, `goal`, `IntensityTarget`),
  plus `AthleteProfile.paceModel` (zone ↔ pace) and `WorkoutDurationEstimator` for distance goals.
- `PlanReconciler` sets `Activity.linkedPlanID`, so for any activity started from a plan **we already know the
  intended step structure without importing steps from HealthKit**.
- Compliance (`icloud-healthkit-compliance-architecture.md`): anything derived from HealthKit data
  (including an intensity category of a performed activity) must **not** go in the CloudKit store. Compute on
  demand or cache in the local-only store.

## 4. Design

### 4.1 Core idea: "quality time", not mean/max/total

Intensity is decided by *how much sustained time was spent at or above threshold-ish effort*, after
removing the artefacts in §2:

- `hardSeconds`: sustained time in Z4–Z5
- `moderateSeconds`: sustained time in Z3
- both also as a fraction of the working (non-warm-up/cool-down) duration

Zone semantics (decided with the athlete):

- **Z3 = tempo** → `medium`. A continuous tempo run is run in Z3.
- **Z4 = threshold** → `high`. A continuous threshold run, or interval work at Z4–Z5, is a hard session.
- A single short hard effort (e.g. a 3 min hill in Z4 inside a 60 min run) must **not** change the category.

Initial ladder (all values live in a `IntensityClassifierParameters` struct so they can be tuned/calibrated
later, cf. MVP3):

```
high     : hardSeconds ≥ max(6 min, 10 % of duration)
medium   : hard + moderate ≥ max(8 min, 15 % of duration)
low      : time above Z1 ≥ 10 % of duration
veryLow  : otherwise (essentially all Z1/below)
```

Worked examples:

| Session | Result |
|---|---|
| 60 min easy, brief Z3 blips | low (excursions < 60 s are debounced) |
| 45 min recovery, 3 min in Z2 | veryLow |
| 2 h long run, 12 min in Z3 | low (15 % of 2 h = 18 min) |
| 90 min run, last 20 min in Z3 (fast finish) | medium |
| 30 min continuous tempo in Z3 | medium |
| 20 min continuous threshold in Z4 | high |
| 5×3 min at Z4 with recoveries | high |
| 60 min run with one 3 min hill in Z4 | low (3 min < 6 min floor, and < 8 min for medium) |

Known edge: very short reps (e.g. 4×1 min = 4 min hard) fall under the 6 min floor and read as `medium`/`low`.
Plan-guided evaluation (§4.3) counts the planned step time, so this mostly affects unlinked activities; the floor is a
tunable parameter.

"Sustained" = an excursion counts only if it lasts ≥ `minExcursion` (default 60 s) after lag compensation.
This is what stops an easy run that briefly touches Z3 from becoming "medium".

### 4.2 Planned activities (pure, no sensor data)

Walk the `StructuredWorkout` steps, excluding `.warmup`/`.cooldown`, convert each step to (seconds, effective zone):

- `.heartRateZone(z)` → z; `.heartRateRange` → zone of its midpoint via the athlete's zone model
- `.pace(range)` → nearest zone via `PaceModel`
- `.rpe(n)` → fixed mapping (≤3 → Z1–2, 4–5 → Z3, 6–7 → Z4, ≥8 → Z5)
- `.power` → unmapped for now (no power model) → falls back to the default below
- no target → default by `StepKind` (`.work` → Z3, `.recovery` → Z1, others excluded)

Distance goals are converted to seconds by `WorkoutDurationEstimator`. Then apply the §4.1 ladder.
Recovery steps inside intervals count as time but not as quality time, so 5×1 km at Z4 with jog recoveries
is `high`; a 90 min run with a final 20 min at Z3 is `medium` (≥ 15 %).

### 4.3 Performed activities

Three evidence sources, combined in order of trust:

1. **Plan-guided (activity has `linkedPlanID`)** — implemented as `PlanGuidedIntensityClassifier`.
   The plan states the intent; heart rate verifies it.
   - *Verified plan.* If every plan step has a fixed (time) duration, the steps are laid out on the
     activity's timeline (assuming they ran back to back from the start). Each hard or tempo step
     (zone ≥ 3, not warm-up/cool-down) is checked against the **lag-corrected effort** (§4.3.2's series, so
     no separate window shift is needed): the P90 effort during the step gives the zone reached, and the
     step counts at `min(planned, reached)`. The ladder is applied to these verified zones, so short reps
     that the HR-only debounce would drop still count, and skipped or under-performed reps don't.
     Steps with < 50 % heart-rate coverage are taken at their planned zone.
   - *Unplanned effort.* Whole-activity HR-only evidence (§4.3.2) can move the verified category
     **one level up, never more** (HR can rise from heat/drift/illness without the effort changing).
     It never moves it down: the per-step check already covers under-performance.
   - *Plan can't be laid out* (distance or open steps): the planned category is moved one level towards the
     measured one, in either direction.
   - No usable heart rate: the planned category, `source = .planned`, low confidence.
   - Confidence: `high` only when the verified category agrees with the measured one and ≥ 75 % of hard/tempo
     step time could be checked.
   The recovery-step handling in the original sketch (judging recoveries on minimum HR) turned out to be
   unnecessary: the lag correction already stops a slow fall from being read as continued effort, and only
   hard/tempo steps affect the category.

2. **HR-only (unlinked, no steps)** — smooth the HR series, apply the same lag compensation
   (shift/first-order deconvolution of the rise), debounce excursions shorter than `minExcursion`,
   build `TimeInZone` from the cleaned series, apply the §4.1 ladder.

3. **Pace as structure evidence (running only, needs speed data)** — detect bouts as alternating fast/slow
   segments at ~30 s scale (bimodal smoothed speed, or high coefficient of variation on flat terrain).
   Pace is used to *find* bouts and to *promote confidence*, **never on its own to grant `high`**:
   - a pace-detected bout is only credited if lag-shifted HR in its window corroborates (≥ Z3);
   - HR-detected hard effort with slow pace is kept as hard (hill sprints): HR decides magnitude,
     pace decides structure;
   - true grade-adjusted pace needs an altitude stream — out of scope for v1, listed as a follow-up.

Where a sport has no HR data, fall back to `perceivedExertion` (Borg CR10 mapping as in
`DurationRPECalculator`), else `nil` (unknown, not a guess).

### 4.4 Output type

```swift
public enum IntensityCategory: Int, Comparable, Codable { case veryLow, low, medium, high }

public struct IntensityAssessment {
    public var category: IntensityCategory
    public var source: Source            // .planned / .measured / .blended
    public var confidence: Confidence    // .low / .medium / .high
    public var hardSeconds: TimeInterval
    public var moderateSeconds: TimeInterval
}
```

`source` mirrors the "estimated vs measured" labelling already planned for TRIMP (MVP2-8) so the UI can
label consistently.

### 4.5 Where it lives

`Sources/TrainingCore/Intensity/`: `IntensityCategory`, `IntensityAssessment`, `IntensityClassifierParameters`,
`PlannedIntensityClassifier`, `PerformedIntensityClassifier` (+ `HRLagCompensator`, `BoutDetector` internals).
Surfaced through `TrainingModel` (e.g. `intensity(of: Activity)` / `intensity(of: PlannedActivity)`) and as
a field on `ActivitySummary`. **No persistence** for performed results in v1 (derived health data; compute on demand,
cache locally only if profiling demands it).

## 5. Phasing

1. `IntensityCategory` + `PlannedIntensityClassifier` + tests (pure, no HealthKit dependency).
2. HR-only performed classifier: debounce + lag compensation, tests on synthetic profiles
   (5×3 min intervals with realistic HR lag, easy run with Z3 blips, tempo, long run with fast finish).
3. Plan-guided per-step evaluation and the plan/measured blend.
4. **Importer spike**: import `SpeedSample`s (currently missing) and check on a real device what
   `HKWorkoutActivity`/`HKWorkoutEvent` contain for WorkoutKit-run workouts; if step boundaries are present,
   use them as the segmentation instead of the plan. Then pace/bout detection.
5. App: colour/label on cards and detail (revives MVP2-9), stats aggregation.

## 6. Validation

Hand-label ~20 of the athlete's real activities (easy / long / tempo / fartlek / intervals / hills) and report the
agreement of each classifier, plus the confusion matrix. Thresholds are parameters, tuned against that set.

## 7. Open questions

1. ~~Ladder thresholds and categories~~ — **resolved**: tempo = Z3 = `medium`, threshold = Z4 = `high`, a single
   3 min hill in a 60 min run stays `low`; `veryLow` is derived from data, not reserved for labelled recovery
   workouts. Still open: is the 6 min / 10 % floor for `high` right for short-rep sessions?
2. `AthleteProfile.paceModel` requires a threshold pace: where does it come from today, and is it trustworthy
   enough to drive bout detection?
3. ~~Default for plan-linked activities~~ — implemented as proposed (trust the plan, verify with heart rate,
   move at most one level on contradiction). **Assumed accepted when phase 3 was started; revisit on real data.**
4. v1 scope: running only for pace/bout logic, other sports HR-plan only?
5. Is the importer spike (speed samples + workout events) acceptable inside this todo, or its own todo?
