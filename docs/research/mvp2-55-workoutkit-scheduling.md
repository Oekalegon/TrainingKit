# MVP2-55 research — scheduling planned workouts on the Watch

Research ahead of MVP2-55, "the app's scheduler": the piece that keeps the Watch's Workout app in
step with the athlete's `PlannedActivity`s. `WorkoutKitBridge` already maps a workout and wraps
`WorkoutScheduler.schedule`/`remove` (MVP2-39). What's missing is the thing that decides *what*
should be on the Watch and *when* to sync it. This note covers what WorkoutKit allows, what the
current bridge gets wrong for this job, and a proposed design.

## 1. What WorkoutKit offers

`WorkoutScheduler` (iOS 17, watchOS 10, macOS 15; the package targets 26 everywhere):

| API | Notes |
|---|---|
| `WorkoutScheduler.shared` | Only instance; no public initializer, so no injected fake. |
| `isSupported` | Whether the device supports scheduled workouts. Check before showing any UI. |
| `requestAuthorization()`, `authorizationState` | `.authorized`, `.denied`, `.notDetermined`, `.restricted`. Wrapped by `WorkoutKitAuthorization`. |
| `schedule(_ plan: WorkoutPlan, at: DateComponents)` | Adds an entry. Non-throwing. |
| `scheduledWorkouts: [ScheduledWorkoutPlan]` | Only the entries *this app* scheduled. Each has `plan`, `date` (`DateComponents`) and `complete`. |
| `maxAllowedScheduledWorkoutCount` | A cap on entries the app may hold. Apple's WWDC23 session says 15. |
| `markComplete(_:at:)` | Lets the app mark an entry done (e.g. after a manual link). |
| `remove(_:at:)`, `removeAllWorkouts()` | Remove one entry, or all of them. |

How the Watch shows it (WWDC23 session 10016):
- The app gets its own section at the top of the Workout app, with its icon and name, showing the
  **next workout for today**. One tap starts it.
- "View More" lists workouts **7 days back and 7 days ahead**. Entries outside that window are
  stored but not shown.
- **Up to 15 workouts at a time.** Read `maxAllowedScheduledWorkoutCount` at runtime rather than
  hard-coding 15.
- Sync to the Watch is handled locally by the system. The app gets no callback or delivery
  confirmation.
- A scheduled entry carries no health data: only the workout, the date, and whether it was
  completed. The workout itself is recorded normally: starting a scheduled entry on the Watch
  saves an `HKWorkout` with heart rate, distance and energy, which `HealthKitActivityImporter`
  imports like any other activity.
- WorkoutKit adds an extension on `HKWorkout` that returns the `WorkoutPlan` a recorded workout
  was started from, when there is one. That's an exact link from an imported activity to the plan
  it fulfilled (see §4.4). Check this on a device: it isn't in the online docs index.

Other paths that don't use the scheduler:
- **Preview / "Add to Watch"**: a SwiftUI `workoutPreview` modifier on iOS shows a system sheet
  that saves one workout to the Workout app. On watchOS, `WorkoutPlan.openInWorkoutApp()` opens it
  in the Workout app. The user then manages these workouts themselves, with no date and no
  completion read-back. This is useful as a manual "send this workout to my Watch" action, and as
  the fallback when scheduling is broken (§1.1).
- **Export**: `WorkoutPlan.dataRepresentation` / `init(from:)` serialise a plan as a `.workout`
  file for sharing. Not needed for MVP2-55.

What WorkoutKit can't do:
- No time-of-day slots in the Watch UI. `DateComponents` could carry a time, but the bridge uses
  the day only, which matches `PlannedActivity.date`.
- No wake-up or notification when the athlete completes an entry. The app sees `complete` only
  the next time it reads `scheduledWorkouts`.
- No library separate from schedules. Every entry is a dated `WorkoutPlan`.
- No test seam. `WorkoutScheduler` is `final` with only `.shared`, so tests need a protocol of our
  own around it (§4.5).

### 1.1 Known platform issue

Since iOS 18.2, some users find that scheduled workouts show up in `scheduledWorkouts` on the
iPhone but never reach the Watch
([Apple Developer Forums thread 767737](https://developer.apple.com/forums/thread/767737)). Other
apps are affected too, including TrainingPeaks. The issue was still open in iOS 26 betas as of
July 2025. It looks tied to the account's iCloud Health data rather than to the app. Resetting
the Watch or rescheduling didn't help. Apple's suggested step was `removeAllWorkouts()` and
schedule again. Implications:
- We can't tell from the phone whether an entry reached the Watch, so don't show "on your Watch"
  as a fact. Show "sent to Watch" at most.
- Offer the preview / "Add to Watch" path as a manual fallback.
- A "reset Watch schedule" action (`removeAllWorkouts()` then a full re-sync) is cheap to add and
  is the one step Apple suggested.

## 2. What the MVP2-39 bridge got wrong for a scheduler

Fixed on this branch; see §5, item 4. As MVP2-39 shipped it, `WorkoutKitBridge.schedule` gave the `WorkoutPlan` the id `workout.workoutKitID ?? UUID()`, and
`unschedule` matched entries on that id plus the day. That breaks down once something schedules
for real:

1. **Nothing ever sets `StructuredWorkout.workoutKitID`.** `sync(_:)` returns an id but nothing
   stores it. So every `schedule` mints a random id, and `unschedule` exits early because the id
   is `nil`. Moving or deleting a plan leaves its old entry on the Watch, and it keeps taking up
   one of the 15 slots.
2. **The id belongs to the library workout, not the plan.** If one workout is planned on several
   days (e.g. "Easy run" three times a week), every entry gets the same `WorkoutPlan.id`:
   - Two plans of the same workout on one day can't be told apart. `unschedule` removes both.
   - A completed entry can't be traced back to its `PlannedActivity`, so the `complete` flag and
     `HKWorkout`'s plan link are of no use for reconciliation.
   - It's unclear whether WorkoutKit accepts the same id on several dates. Nothing documents
     that.
3. **Changes to a workout's content go unnoticed.** Editing the library workout after scheduling
   leaves the old version on the Watch. Nothing compares the two.

**Recommendation: use `PlannedActivity.id` as the `WorkoutPlan.id`.** Each entry then maps to
exactly one plan:
- No id needs to be stored, since the plan's own id is stable. `StructuredWorkout.workoutKitID`
  is then only needed for `structuredWorkout(from:)` round-trips, and could be deprecated.
- `unschedule` can match on id alone. Matching on the day becomes a sanity check, and a moved
  plan is found wherever it was.
- `scheduledWorkouts[].complete` and `HKWorkout`'s plan id point straight at a `PlannedActivity`.
- `WorkoutPlan` is `Equatable`/`Hashable`. The scheduler can rebuild the desired plan and compare
  it with what WorkoutKit holds to catch edits (point 3), without storing a fingerprint.

This changes the `schedule`/`unschedule` signatures in `TrainingWorkoutKit` (MVP2-39's API), and
the design doc §5.2 needs updating to match.

## 3. When the scheduler can run

WorkoutKit never wakes the app, so the window has to roll forward whenever the app gets a chance
to run. Options, from most to least reliable:

| Trigger | Reliability | Notes |
|---|---|---|
| A plan is added, moved, deleted or edited; a library workout is edited; a calendar import runs | Certain | The app is running. Sync right after the model write succeeds. |
| App goes to the foreground (`scenePhase == .active`) | Certain, but needs the athlete to open the app | Covers the window rolling over at midnight. |
| HealthKit background delivery for workouts (`HKObserverQuery` + `enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)`) | Good. Fires when a workout is saved, often right after a scheduled one finishes | Needs the HealthKit background-delivery entitlement. It's also the natural moment to import and reconcile the new activity. |
| `BGAppRefreshTask` | Best effort, at the system's discretion | Daily-ish top-up so the next 7 days stay populated if the app isn't opened. |

The scheduler should be **idempotent**: each run compares what *should* be scheduled with what
*is*, so any trigger can call it any number of times.

## 4. Proposed design

### 4.1 Which plans should be on the Watch

A plan is *eligible* when:
- its date is in `[today, today + horizon]` in the athlete's time zone, where `horizon` is 6 days
  by default (matching the Watch's 7-day view), and
- it isn't linked to an activity (`completedActivityID == nil`), and
- it maps to a `CustomWorkout`. `customWorkout(from:)` doesn't throw for it, and the reason is
  kept for the UI when it does.

Order eligible plans by date and keep the first `maxAllowedScheduledWorkoutCount`. Plans beyond
the cap get scheduled on a later run as the window moves. With a 7-day window, hitting 15 would
take two or more workouts a day, so in practice the cap only matters if the horizon is set
longer.

Past entries: remove entries dated before today that aren't complete (missed workouts), so they
don't use up slots. Leave completed past entries for the Watch's "last 7 days" view, and remove
them only when the cap is reached.

### 4.2 Split between Core and the bridge

- **`TrainingCore` — `WorkoutSchedulePlanner`** (pure, no WorkoutKit dependency, like
  `CalendarImportPlanner`). Input: plans, workouts, today, the athlete's calendar, horizon, cap,
  and a WorkoutKit-free description of the current entries (`plan id`, `day`, `complete`, and a
  content token supplied by the bridge). Output: a list of `schedule` / `remove` / `replace`
  operations, plus `unschedulable` plans with a reason.
- **`TrainingWorkoutKit` — `WorkoutScheduleSync`** (thin). Reads `scheduledWorkouts`, builds the
  desired `WorkoutPlan`s, asks the planner what to do, applies the operations through a
  `WorkoutScheduling` protocol (the live type wraps `.shared`), and returns a report: scheduled,
  removed, unchanged, unschedulable, and completed entries seen.
- **App**: owns the triggers in §3, authorization, and the UI.

### 4.3 Authorization and UI

- Onboarding is HealthKit + CloudKit only (roadmap). Ask for WorkoutKit permission the first time
  the athlete turns on "Send planned workouts to Apple Watch", or the first time they plan a
  workout, rather than adding a step to onboarding.
- Check `isSupported` first. No paired Watch, or an unsupported device: hide the feature.
- `.denied`: use the same kind of dismissible banner the roadmap describes for revoked HealthKit
  access.
- Plan card: a small "sent to Watch" mark, and a warning when the workout can't be mapped
  ("Watch doesn't support this alert for cycling").
- Settings: an on/off switch, plus "Reset Watch schedule" (§1.1).

### 4.4 Using completion

Three signals, from most to least exact:
1. **`HKWorkout` → `WorkoutPlan.id`** when importing. With per-plan ids this names the
   `PlannedActivity` directly. `PlanReconciler` could take it as a hard match ahead of its
   same-day best-fit heuristic, which also settles the "close runner-up" ambiguity case.
2. **`ScheduledWorkoutPlan.complete`.** A hint that the plan was done even before the HealthKit
   import catches up (design doc §5.2 already notes this).
3. The existing same-day heuristic for activities not started from a scheduled entry.

Going the other way, when the athlete links an activity to a plan by hand, call
`markComplete(_:at:)` so the Watch agrees. A link to an activity removes the plan from the
eligible set but leaves its entry in place, marked complete.

Item 1 touches `TrainingHealthKit` (the importer reads the plan id and carries it on
`Activity.scheduledPlanID`) and `PlanReconciler`. Done as MVP2-120, a separate ticket from the
scheduler: the reconciler matches on the id first, same day only, and falls back to the heuristic
when the plan is gone or on another day. An activity whose plan is already taken stays unlinked.

### 4.5 Testing

- The planner is pure, so it can be unit tested fully: window edges across DST and time zones,
  the cap, moves, deletes, content edits, missed and complete entries, and two plans on one day.
- The sync layer is tested against a fake `WorkoutScheduling`.
- `WorkoutScheduler` itself needs a real iPhone and Watch. A short manual checklist (schedule,
  move, delete, edit, complete on the Watch, read back) belongs in the harness app or the PR.

## 5. Decisions and open questions

Decided:
1. **Ticket scope.** MVP2-55 includes the `HKWorkout` plan-id reconciliation (§4.4, item 1), not
   just the rolling-window scheduler.
2. **Horizon.** Fixed at 7 days (today plus 6), matching what the Watch shows. Not configurable.
3. **Opt-in.** Sending planned workouts to the Watch is on by default once WorkoutKit permission
   is granted. The settings switch can still turn it off.
4. **Per-plan ids (§2).** Done: `WorkoutKitBridge.workoutPlan(for:workout:)` gives each entry its
   plan's id, `schedule` replaces the plan's existing entry (so a move or edit is one call) but
   keeps an identical or completed entry on the plan's day, and `unschedule(_:)` takes only the
   plan. `unscheduleAll(except:)` clears entries scheduled under the old ids. Scheduling goes
   through an internal `WorkoutScheduling` seam, so it's tested against a fake.

Open:
5. **Where the app code lives.** `TrainingApp` isn't in this repository. The planner and sync
   layer can be built and tested here; the triggers and UI go in the app.

## 6. TrainingApp follow-up

The per-plan id change breaks the app's calls and needs app work of its own:
- `unschedule(_:workout:calendar:)` is now `unschedule(_:)`. Drop the extra arguments.
- Moving a plan or editing its workout needs only `schedule`. The `unschedule` call before it is
  now a wasted round-trip.
- Once, after upgrading: call `unscheduleAll(except:)` with the ids of every plan in the store,
  so entries scheduled under the old ids leave the Watch. The scheduler's regular pass can do
  this every run instead.
- `sync(_:)` is deprecated; validate with `customWorkout(from:)` instead.
- Then the MVP2-55 app work proper: the triggers in §3, the permission request and UI in §4.3.

## Sources

- [WorkoutScheduler — Apple Developer Documentation](https://developer.apple.com/documentation/workoutkit/workoutscheduler)
- [Build custom workouts with WorkoutKit — WWDC23 session 10016](https://developer.apple.com/videos/play/wwdc2023/10016/)
- [Build custom swimming workouts with WorkoutKit — WWDC24 session 10084](https://developer.apple.com/videos/play/wwdc2024/10084/)
- [WorkoutKit WorkoutScheduler sync broken with iOS 18.2 — Apple Developer Forums](https://developer.apple.com/forums/thread/767737)
