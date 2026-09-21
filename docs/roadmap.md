# TrainingKit — MVP Roadmap

High-level overview of the planned milestones. For the detailed MVP 1 package design (types, targets, test plan), see [`design/trainingKit-design.md`](design/trainingKit-design.md). Todo IDs referenced below are tracked in the `MVP1`/`MVP2`/`MVP3`/`MVP4`/`MVP5`/`MVP6`/`MVP7`/`FIT` projects.

Note: the numbering here has drifted from the design doc's own §12 "Roadmap seams" table, which only anticipates three post-MVP-1 milestones (plan generator, LLM coach, calibration). As scope got split further, the todo projects ended up as: MVP 2 (manual structured/planned workouts), MVP 3 (calibration — see its own note below), MVP 4 (activity detail, an MVP 1 spillover), MVP 5 (the plan generator/wizard), MVP 6 (the LLM coach), MVP 7 (Athlete tab biometric history). Treat the todo project numbers below as authoritative over the design doc's numbering.

---

## MVP 1 — Core, Persistence and Device Adapters

**Status: active, in progress.**

The foundation: the pure `TrainingCore` model (activities, training load / TRIMP, structured workouts, planned activities, the daily fitness series engine, periodisation, plan guardrails), the `TrainingHealthKit`/`TrainingWorkoutKit`/`TrainingPersistence` adapters, and the first iOS app (`TrainingApp`) — week view, activity detail, athlete account screen.

See §1–§10 of the design doc for the full model. Remaining MVP 1 work (backlog) is mostly UI polish and secondary features on top of the now-working core: HR-zone naming/colors, an 80/20 polarized-training split, HR-over-time/histogram charts on activity detail, an overlapping-activities warning, delete-activity support, and a fitness-metrics explainer sheet.

## MVP 2 — Structured & Planned Workouts

**Status: not started.**

Manual authoring and scheduling, no auto-generation yet. Key pieces, scoped in detail through a design session (2026-09-13):

- **Navigation**: a new tab hosts the workout library (and, later, MVP 5's plan builder). The calendar's `+` on a date is date-aware: today/future opens a sheet to add a Planned Workout or a Race; a past date adds a completed Activity manually (deferred to **MVP 4**).
- **`Race` model**: dated event with a `RaceImportance` (primary/secondary/tertiary); primary is typically the plan's end date, secondary/tertiary get lighter plan adjustments — but that behavior is MVP 5's job, MVP 2 only stores/displays it (with a calendar marker distinguishing primary from secondary/tertiary).
- **`Goal` model**: a *separate* type from `Race` — a non-event target (e.g. "sub-20 5km") with no date and no calendar presence. Modeled in MVP 2; its management UI is an MVP 5 todo.
- **Structured Workout creator** (create/edit/duplicate) plus a 14-workout standard library: recovery, easy, long, tempo, fast finish, long fast finish, fartlek, long fartlek, hill reps, short/long/mixed interval, plus a MaxHR field test and an LTHR field test (Friel 30-min protocol). Duration-based by default; long/track workouts can be distance-based (multiples of 400/200/100m). `SessionType` is extended from its current 7 cases to match this granularity. `StructuredWorkout` gets a `purpose` field (`.general`/`.maxHRTest`/`.lthrTest`); completing a test workout shows a "we measured X — update your profile?" confirmation rather than writing silently. `AthleteProfile` tracks *how* MaxHR/LTHR was obtained (`.formula`/`.workout`/`.labTest`, ranked by reliability in that order), with a manual lab-test entry path.
- **Create/Edit Planned Workout sheet**: runs the hypothetical addition through the existing `PlanEvaluator` guardrails and warns (never blocks) on risk — one source of truth shared with MVP 5's generator rather than a second warning system.
- **TRIMP-confidence estimation** for planned/no-HR activities: map each step's `IntensityTarget` through the athlete's HR zones to a synthetic HR profile, run the existing TRIMP calculator, and label the result "estimated" vs "measured" everywhere it's shown. Once a structured workout has ≥1 completed activity linked via reconciliation, refine its estimate using the **median** actual TRIMP from those linked activities (a workout-specific precursor to MVP 3's general calibration, which supersedes it).
- **`PlanReconciler`**: links a completed `Activity` to a `PlannedActivity` (same-day, same-sport-family, best fit on the plan's explicit duration/distance; a close runner-up is flagged ambiguous rather than silently resolved; only newly imported activities are auto-matched, and manual links are same-day only). Manual link/unlink lives on the Activity Detail sheet.
- **Timeline card states**: *completed* (solid, leading vertical bar colored by type/effort), *planned-future* (same bar, hatched pattern, same hue, less saturated), *missed* — a planned workout whose date has passed with no linked activity (whole card hatched, secondary-color text throughout), and *merged* (solid like completed, showing both planned and actual duration/distance). A missed workout's estimated TRIMP is excluded from CTL/ATL/TSB, monotony/strain, and aggregate distance/duration stats — those reflect what actually happened; future planned workouts continue to feed the projected series as already designed.
- **Onboarding**: HealthKit + CloudKit permissions only (no profile setup), blocks first launch; a permission revoked later shows a dismissible banner rather than re-running onboarding.

This is the foundation the MVP 5 plan generator builds on: everything it produces is the same `PlannedActivity`/`StructuredWorkout` data a user can already create by hand here.

## MVP 5 — Plan Assistant

**Status: not started.**

The deterministic plan generator: `PlanPreferences` (training days, per-day sport/session-type, starting volume, weekly ramp), a Create Plan wizard sheet (training days, primary race/target, preferred long-run/interval days, recovery-week cadence, max TRIMP ramp), `PlanGenerator` that lays out cycles via `CycleLayoutBuilder` (already built in MVP 1) and fills them with library workouts, iterated against `PlanEvaluator`'s guardrails via a fixed set of heuristic adjustments — no LLM involved yet. Also covers a set of standard plans by target distance.

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
