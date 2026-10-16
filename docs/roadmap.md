# TrainingKit — MVP Roadmap

High-level overview of the planned milestones. For the detailed MVP 1 package design (types, targets, test plan), see [`design/trainingKit-design.md`](design/trainingKit-design.md). Todo IDs referenced below are tracked in the `MVP1`/`MVP2`/`MVP3`/`MVP4`/`MVP5`/`MVP6`/`MVP7`/`FIT` projects.

Note: the numbering here has drifted from the design doc's own §12 "Roadmap seams" table, which only anticipates three post-MVP-1 milestones (plan generator, LLM coach, calibration). As scope got split further, the todo projects ended up as: MVP 2 (manual structured/planned workouts), MVP 3 (calibration — see its own note below), MVP 4 (activity detail, an MVP 1 spillover), MVP 5 (the plan generator/wizard), MVP 6 (the LLM coach), MVP 7 (Athlete tab biometric history). Treat the todo project numbers below as authoritative over the design doc's numbering.

---

## MVP 1 — Core, Persistence and Device Adapters

**Status: shipped in 0.1.0; the backlog below continues on `develop`.**

The foundation: the pure `TrainingCore` model (activities, training load / TRIMP, structured workouts, planned activities, the daily fitness series engine, periodisation, plan guardrails), the `TrainingHealthKit`/`TrainingWorkoutKit`/`TrainingPersistence` adapters, and the first iOS app (`TrainingApp`) — week view, activity detail, athlete account screen.

See §1–§10 of the design doc for the full model. Remaining MVP 1 work (backlog) is mostly UI polish and secondary features on top of the now-working core: HR-zone naming/colors, an 80/20 polarized-training split, HR-over-time/histogram charts on activity detail, an overlapping-activities warning, delete-activity support, and a fitness-metrics explainer sheet.

## MVP 2 — Structured & Planned Workouts

**Status: shipped in 0.2.0.** Still open from it: the marathon pace workout (needs pace zones, MVP 8) and adding a completed activity by hand from a past calendar day (MVP 4).

Manual authoring and scheduling, no auto-generation yet. Key pieces, scoped in detail through a design session (2026-09-13):

- **Navigation**: a new tab hosts the workout library (and, later, MVP 5's plan builder). The calendar's `+` on a date is date-aware: today/future opens a sheet to add a Planned Workout or a Race; a past date adds a completed Activity manually (deferred to **MVP 4**).
- **`Race` model**: dated event with a `RaceImportance` (primary/secondary/tertiary); primary is typically the plan's end date, secondary/tertiary get lighter plan adjustments — but that behavior is MVP 5's job, MVP 2 only stores/displays it (with a calendar marker distinguishing primary from secondary/tertiary).
- **`Goal` model**: a *separate* type from `Race` — a non-event target (e.g. "sub-20 5km") with no date and no calendar presence. Modeled in MVP 2 (`Goal` with a `GoalTarget` of time over a distance, a volume per week/month/year, or free text; a synced `GoalStore`; `TrainingModel.goals`); its management UI is an MVP 5 todo.
- **Structured Workout creator** (create/edit/duplicate) plus a standard library of running workouts: recovery, easy, long, tempo, fast finish, long fast finish, fartlek, long fartlek, hill reps, short/long/mixed interval, plus a MaxHR field test and an LTHR field test (Friel 30-min protocol). The creator itself shipped as MVP2-140 (a synced `WorkoutTemplateStore` on the kit side; the editor is in the app). Shipped so far: recovery, easy, long and tempo runs, plus Base Full-out hill sprints and Short interval run in time and track versions (MVP2-105), and (MVP2-106) Fast Finish Run, Long run with fast finish, Cruise, Long and Mixed Interval Runs, Fartlek (Zone 4 and Zone 5), Long Fartlek, Hill Repetition Runs and Sarcomere Runs (hill repetitions run downhill, at RPE 8 so the descent stays controlled). Fartlek is two templates because a template's zone is fixed. The marathon pace workout waits for pace zones (MVP8). Duration-based by default; long/track workouts can be distance-based (multiples of 400/200/100m). `SessionType` deliberately stays a small, generic set of broad categories rather than growing a case per library workout; a template's specifics (fartlek, fast finish, the interval variants) live in the template itself. `StructuredWorkout` gets a `purpose` field (`.general`/`.maxHRTest`/`.lthrTest`); completing a test workout shows a "we measured X — update your profile?" confirmation rather than writing silently. `AthleteProfile` tracks *how* MaxHR/LTHR was obtained (`.formula`/`.workout`/`.labTest`, ranked by reliability in that order), with a manual lab-test entry path. The first part has shipped as MVP2-56: `HeartRateZoneSettings.maxHeartRateSource` (`.formula`/`.workout`), and a raise-only, athlete-confirmed max HR update whenever an ordinary workout holds a heart rate above the current max. The test workouts have shipped as MVP2-153: `StructuredWorkout.purpose` (and `WorkoutTemplate.purpose`, carried on instantiate, persisted, absent in old data = `.general`, and kept in calendar files) and the two built-in templates. The max HR test is a 10-minute Zone 1 warmup and 5-minute Zone 2 ramp-in, three 3-minute efforts at RPE 9 with 1-minute Zone 1 recoveries, a 3-minute all-out effort (RPE 10) and a 5-minute cooldown. Friel's LTHR test is the same warmup and ramp-in, one 30-minute effort at RPE 9, and a 5-minute cooldown; the result is the average heart rate over the effort's last 20 minutes. Both aim at perceived exertion, not heart-rate zones, because the zones are what the tests set. Measuring the results shipped as MVP2-154: `FieldTestMeasurer` and `TrainingModel.fieldTestResult(forActivity:)` read the max HR (the held peak) or the LTHR (the average of the last 20 minutes of the effort) off the activity linked to the test's plan, and `applyFieldTestResult` records it, date-effective, after the athlete confirms. A test may lower the max; ordinary workouts still only raise it. The source is `MaxHeartRateSource.fieldTest(activityID:)`, and `HeartRateZoneSettings.lactateThresholdSource` tracks the LTHR (`.manual` or `.fieldTest`). `.labTest(measuredOn:)` shipped as a source for both (entered by the athlete from a lab result), and the sources are ranked by reliability (`reliabilityRank(asOf:)`, `isReplaceable(by:asOf:)`: formula < manual < workout < field test < lab test) so an automatic update never replaces a better one. A lab test ages: after 2 years (max HR) or 90 days (LTHR) it ranks below a new field test. `FieldTestResult.replacesMoreReliableSource` warns when a test would replace a fresh lab value. The app shows the prompt (MVP2-155) and records lab tests in the heart-rate settings (MVP2-158).
- **Create/Edit Planned Workout sheet**: runs the hypothetical addition through the existing `PlanEvaluator` guardrails and warns (never blocks) on risk — one source of truth shared with MVP 5's generator rather than a second warning system.
- **TRIMP-confidence estimation** for planned/no-HR activities: map each step's `IntensityTarget` through the athlete's HR zones to a synthetic HR profile, run the existing TRIMP calculator, and label the result "estimated" vs "measured" everywhere it's shown. Once a structured workout has ≥1 completed activity linked via reconciliation, refine its estimate using the **median** actual TRIMP from those linked activities (a workout-specific precursor to MVP 3's general calibration, which supersedes it). Shipped as `LinkedActivityRefinedEstimator` (wrapped around the base estimator by `TrainingModel` for the load series and calendar export): the estimate of a workout is the base estimate times the recency-weighted median (a run's weight halves for every 60 days it is older than the newest run; a run whose duration is far from the workout's, such as a session cut short, is skipped) of `actual / base estimate` over completed plans of the same library workout or template. Comparing estimates (not raw TRIMP) is what scales it to the template's parameters and to the zones its steps target; confidence rises with each reference (0.7 → 0.85 → 0.925, capped 0.95). A per-plan `expectedLoadOverride` still wins.
- **`PlanReconciler`**: links a completed `Activity` to a `PlannedActivity` (an activity started from a scheduled Watch workout, `scheduledPlanID`, is matched to exactly that plan first; otherwise same-day, same-sport-family, best fit on the plan's explicit duration/distance; a close runner-up is flagged ambiguous rather than silently resolved; only newly imported activities are auto-matched, and manual links are same-day only). Manual link/unlink lives on the Activity Detail sheet.
- **Timeline card states**: *completed* (solid, leading vertical bar colored by type/effort), *planned-future* (same bar, hatched pattern, same hue, less saturated), *missed* — a planned workout whose date has passed with no linked activity (whole card hatched, secondary-color text throughout), and *merged* (solid like completed, showing both planned and actual duration/distance). A missed workout's estimated TRIMP is excluded from CTL/ATL/TSB, monotony/strain, and aggregate distance/duration stats — those reflect what actually happened; future planned workouts continue to feed the projected series as already designed.
- **Venue** (MVP2-151): `Sport` stays broad and a separate optional `Venue` (`.indoor(.treadmill/.track)`, `.outdoor(.track/.road/.trail/.offtrail)`) says where, carried by activities, workouts, templates, calendar exports and the athlete (`mainVenue`, the usual venue for `mainSport`). The venue is set on the WorkoutKit `CustomWorkout.location`, so starting a planned run on the Watch no longer asks "Indoor or Outdoor?". A template can leave the venue open, restrict it to outdoor, or fix it (the track intervals are an outdoor track); HealthKit's indoor-workout flag fills it on import. The athlete can change a performed activity's sport and venue (`TrainingModel.setSport`, flagged `isSportEdited` so re-imports and join rebuilds keep it; `refreshPaceHistory` follows). Unless edited, an activity linked to a plan takes the plan's sport and venue (else the athlete's usual venue, else the recorded one) on auto-match, manual link, re-import and join rebuild; the reconciler still matches indoor only with indoor and outdoor with outdoor. The plan editor's venue picker, the activity-detail picker and the default sport/venue setting are in the app.
- **Onboarding** (MVP2-147, shipped in the app): HealthKit + CloudKit permissions only (no profile setup). A first-run introduction explains both and can be left at any step, so it doesn't block the app. A dismissible banner covers "Health never connected" (once plans exist) and "iCloud isn't available" (the data stays on the device). HealthKit never says whether read access was granted or later turned off, so a revocation isn't detected: the Apple Health row says where to turn access back on. Initial-sync progress isn't shown.

This is the foundation the MVP 5 plan generator builds on: everything it produces is the same `PlannedActivity`/`StructuredWorkout` data a user can already create by hand here.

## MVP 5 — Plan Assistant

**Status: not started.**

The deterministic plan generator: `PlanPreferences` (training days, per-day sport/session-type, starting volume, weekly ramp), a Create Plan wizard sheet (training days, primary race/target, preferred long-run/interval days, recovery-week cadence, max TRIMP ramp), `PlanGenerator` that lays out cycles via `CycleLayoutBuilder` (already built in MVP 1) and fills them with library workouts, iterated against `PlanEvaluator`'s guardrails via a fixed set of heuristic adjustments — no LLM involved yet. Also covers a set of standard plans by target distance.

Groundwork laid for paradigms (MVP5-102/103): `CyclePhase` is a named, paradigm-defined value rather than a fixed enum, and each micro carries a separate `MicroLoadRole` (build/recovery/taper/race) that rules such as build progression read (MVP5-113). Stored cycles written with the old enum still decode.

Several plans, one active at a time (MVP5-124): a `TrainingPlan` (draft/active/archived) groups planned workouts and cycles through their `planID`; only the active plan feeds the fitness series, statistics, activity matching and calendar export, and data from before plans existed is adopted into a "Current plan". The generator's proposal and commit target a plan; the Plans screen is MVP5-125.

Run availability (MVP5-104): `RunAvailability` (free `DaySlot`s per `Weekday`, independent of the paradigm and stored as `AthleteProfile.runAvailability`, synced with the preferences) and `PlanPreferences` carrying it as the generator's input; day parts are `.morning`, `.afternoon` and `.evening` (MVP5-129; the old combined `afternoonEvening` still decodes to the last two); the number of runs per weekday is its own field, `runsPerDay` (MVP5-131); the settings screen (MVP5-105) is still to do.

Per-slot options (MVP5-127): `SlotOptions` (`longRunPossible`, default true; `trackAvailable`, default false) per weekday and slot on `RunAvailability`, decoding unchanged from stored availability; the generator rules (MVP5-119) and the app toggles (MVP5-128) are still to do.

Run types per micro day (MVP5-110): `RunType` (recovery, easy, long, threshold, interval) maps to an `IntensityCategory` and to the small generic `SessionType`; `PlanPreferences.dayRunTypes` holds the allowed types per 0-based micro day, where a day allows the types it names plus every type no day names (a named type is tied to its days); day assignment (MVP5-119) and the picker (MVP5-112) are still to do.

See design doc §8 and the "Roadmap seams" table (§12) for how this plugs into MVP 1 without reshaping the core.

## MVP 6 — AI Coach

**Status: not started.**

The LLM tool layer described in design doc §11 (there labelled "MVP 3", predating this project split): the provider-neutral `TrainingTools` registry (`ToolRegistry`, `ToolSchema`, `PlanSandbox`) that exposes athlete data and plan operations to a model as typed tools — the LLM never computes fitness numbers itself, it calls tools that do, and every write lands in a sandbox the user must explicitly commit. Covers the tool set itself, the `TrainingToolsAnthropic` adapter (Messages API tool-use loop), the `TrainingToolsFoundationModels` on-device adapter, and the sandbox diff/commit confirmation UI. Reuses MVP 5's `PlanGenerator`/`PlanEvaluator`/`PlanStore` seams unchanged.

## MVP 7 — Athlete Tab History

**Status: not started.**

Show a history of biometrics (RHR, MaxHR, LTHR, and others) over time on the Athlete tab, rather than only the current value — separated out since MVP 2's MaxHR/LTHR field tests and `measurementSource` tracking (`.formula`/`.workout`/`.labTest`) will start producing a real history of these values worth visualizing.

## MVP 8 — Pace/Power Zones

**Status: not started; scope not yet defined.**

Allow the user to train and plan by pace or power zones instead of heart-rate zones. Touches zone settings, `TRIMP`/load calculation, `IntensityTarget`, and guardrails — deep enough into the core model that it needs its own scoping session before todos beyond the placeholder exist.

## MVP 3 — Calibration

**Status: not started.**

Note: the design doc's §11 (LLM tool layer / coach) predates this project split and is internally labelled "MVP 3" there — the `MVP3` todo project as currently scoped is actually the *calibration* milestone (design doc's "MVP 4"): `ResidualStore` of (expected, actual) load pairs from `PlanReconciler`, a `CalibratedPlanEstimator`, and tuning `TRIMPCoefficients`/`LoadModelParameters`/`PlanGuardrails` from observed data. Also covers TRIMP/calorie and TRIMP/lean-mass derived metrics. Worth reconciling the naming between the design doc and the todo projects before this milestone starts.

## FIT — Garmin/COROS Import (TrainingFIT)

**Status: not started; scope actively being defined.**

A `TrainingFIT` target/second `ActivityImporting` implementation for Garmin/COROS data, sitting alongside `TrainingHealthKit` and `WorkoutKitBridge`. Already-filed scope:

- **FIT/TCX activity import and FIT workout export** (`FIT-1`, `FIT-2`) — the baseline: read a raw Garmin/COROS `.FIT`/`.TCX` file, export `StructuredWorkout`s as `.FIT` workouts.
- **Attach a raw `.FIT` file to backfill sparse-HR activities** (`FIT-3`) — for activities that already exist (e.g. from HealthKit) but are missing HR/GPS detail.

### Strava as a relay for Garmin data

Garmin auto-syncs completed activities to Strava, and Strava's Activity Streams API exposes `heartrate`, `latlng`, and `altitude` streams per activity. That's a second, complementary path into the same Garmin data — no direct Garmin API access needed — alongside the file-based FIT import above. Newly scoped:

- **Strava relay import** (`FIT-4`) — a Strava activity-source/provider adapter that pulls HR/GPS/elevation streams via `get_activity_streams`, keyed by activity ID from `list_activities`.
- **Per-activity import picker** (`FIT-5`) — in the activity detail view, let the user import/attach data for that one activity from either a local `.FIT` file or Strava.
- **Automatic background sync** (`FIT-6`) — periodically pull new Strava activities without a manual per-activity action, once the relay adapter exists.
- **Throttled historical backfill** (`FIT-7`) — Strava's rate limits (15-min and daily caps) make importing an athlete's full history in one shot risky. Investigate a gradual backfill — a bounded batch of older activities per sync cycle — rather than a bulk one-time pull.
- **Duplicate detection & merging across sources** (`FIT-8`) — an activity can now arrive from HealthKit, a `.FIT` file, and Strava. Detect when an incoming activity is the same session as one already stored (matching on time/duration/sport, extending MVP 1's existing `ActivityStore.upsert` dedupe-by-source work, `MVP1-26`/`MVP1-27`/`MVP1-28`) instead of creating a duplicate — but allow genuinely merging data from multiple sources into one activity record.
- **Field-level conflict resolution on import** (`FIT-9`) — when a new import targets an activity that already has data from another source (e.g. FIT-file HR arriving for an activity that already has Strava-derived HR), ask the user which fields to keep vs. replace rather than silently overwriting or silently skipping.

Open question carried over from the discussion: whether the throttled backfill (`FIT-7`) is feasible within Strava's rate limits for a typical athlete's multi-year history, and what a sensible default batch size/cadence looks like — needs investigation before `FIT-7` can be scoped into concrete steps.
