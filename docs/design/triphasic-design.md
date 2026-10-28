# Triphasic (Run Elite): what the skills say, and what the code has (MVP5-100)

This document writes down the triphasic training method of Andrew Snow's *Run Elite* as the user's own
Run Elite skill states it, phase by phase, and sets it against the code that exists today. It is input for
MVP5-137 (dial in the triphasic numbers) and MVP5-138 (ultra). **It changes no triphasic number** (the numbers were dialled afterwards, MVP5-137: [§10](#10-the-numbers-as-decided-mvp5-137)). The same PR adds six built-in workout templates for the structures in the notes (§7.3); the paradigm and its numbers are untouched. Where
the skills disagree, are silent or give a range, the point is listed in [§9](#9-questions-for-the-user)
and not decided here.

## 1. Sources and conventions

The authority is the user's skill `skills/run-elite` in the TrainingSkill repo, and the book notes it is
condensed from. Citations name the file and the entry, so every number can be traced:

| Short | File | Cited by |
|---|---|---|
| **SKILL** | `skills/run-elite/SKILL.md` | line number (`SKILL:22`) |
| **DIR** | `skills/run-elite/directives.md` | directive id (`DIR D-13`) |
| **PACES** | `skills/run-elite/paces.md` | line number |
| **NOTES** | `notes/run-elite.md` | the section or id (`NOTES D-24`, `NOTES Chapter 17 examples`) |

`SKILL.md` and `directives.md` are condensed from NOTES ("the source of truth", `SKILL:15`; `DIR:3`) and
number the same directives, `D-nn` and `P-nn`. The three files in `skills/run-elite` carry the rules; the
worked examples that give the only interval lengths (§4.3) exist only in NOTES, so NOTES is cited for them.
Chapter references are the book's, as NOTES gives them.

**Naming.** The skills call the phases Conditioning, Base, **Support**, Specific and Taper (`SKILL:22`).
The code and the ticket call Support **structural** (`CyclePhase.structural`). This document uses
"structural (Support)" and takes them to be the same stage.

**Fractions.** The skills give intensities as a **percentage of race speed**, not of pace (`DIR:12`,
`PACES:11-21`). `StepTargetResolver` divides the race pace by the fraction, so the two agree: 1.05 is 5 %
faster than race pace (`StepTargetResolver.swift`, doc comment). The percentages come from the book's
marathon table (Chapter 16, `PACES:3-4`); for other distances the skills apply the same percentages to the
goal race pace and call that an assumption (`PACES:31-33`).

**Status words** in the code tables: **match** (the code value is what the skills say), **differs** (the
code has a value and it is not the skills'), **not modelled** (the code has nowhere to put it yet), and
**skills silent** (nothing to compare).

**Things that are not from the book.** The skills label them: the 110 % longest-run limit (`DIR D-39`),
the heart-rate mapping (`PACES:41-53`) and pace estimates. This document keeps that labelling.

## 2. What the skills do not say

Four things the ticket asks for are not in the skills in the form a plan generator needs. They are the
main open questions ([§9](#9-questions-for-the-user)):

1. **Interval work-length ranges and repetition counts.** For hill sprints and strides the skills give
   numbers; for the Structural (Support) and Specific interval work they give worked examples only
   (§4.3, §5.3) and no range. Any range for `SessionProfile.workLength` or `workCount` is a choice.
2. **A definition of "hard" for placing sessions.** The skills speak of *quality sessions* (Support), *key
   workouts* (Specific) and *hill-sprint sessions* (Base). They do not say which of these are hard days, nor
   give spacing for Base or Support.
3. **Time or load shares per intensity category and speed level.** Only Base ("at least 80 %" at the two
   extremes, unit unclear), Support ("80 % of mileage at easy pace") and Specific ("most miles very easy",
   default more than 50 %) have a share, and the unit differs (time or distance).
4. **Session counts for a 10- or 14-day micro.** The skills say "per microcycle" for Support quality and say
   "per week" for hill sprints and the final-weeks quality; they never scale a count with the micro length
   (the user's own test of the skill found the same, `NOTES Open questions, point 1`).

## 3. The structure: phases, lengths, flex, micro

### 3.1 Phase order and lengths

| Phase | Length | Source |
|---|---|---|
| Conditioning (optional) | No set length: until the athlete runs the target run days per week, at at least 50 % of peak volume, without pain | `DIR D-40`; `NOTES Conditioning (Chapter 15)` |
| Base | At least 6 weeks (42 days), "arbitrarily long" (hard) | `DIR D-03`; `DIR:16` |
| Structural (Support) | 6 weeks; starts 12 weeks before the taper, i.e. 91 days before race day with a separate 1-week taper | `DIR D-29`, `D-12` |
| Specific | 6 weeks = days 8-49 before the race | `DIR D-30` |
| Taper | 1 week, a separate stage, days 1-7 (Chapter 14 allows 1-3 weeks) | `DIR D-31` |

Days before the race (race day 0): taper 1-7, Specific 8-49, Support 50-91, Base more than 91
(`SKILL:94-99`). The book itself says Support starts "12 weeks before the primary race"; counting the
separate taper that is 13 weeks, and the skill uses 91 days and says to confirm it with the athlete
(; `SKILL:101`; `NOTES D-12`). Why six weeks: "a system improves for only about six weeks"
(`NOTES P-10`).

The phase lengths are stated for a marathon plan. Nothing in the skills lengthens or shortens Structural or
Specific for another race distance.

### 3.2 How the phases flex with the lead time

What the skills say:

| Situation | Rule | Source |
|---|---|---|
| Short on time | Support "can be skipped"; the plan then goes Base to Specific. Do not flag its absence. "Short" is read as under about 13 weeks to the race; the notes themselves ask what the book means | `SKILL:22`, `SKILL:101`; `DIR D-12`; `NOTES Support (Chapter 12)` |
| Conditioning | Optional; skipped when the athlete already runs regularly | `NOTES Conditioning (Chapter 15)` |
| Base | At least 6 weeks (hard); no maximum | `DIR D-03` |
| Specific | 6 weeks. **No rule for shortening it** | `DIR D-30` |
| Taper | 1 week; up to 3 weeks allowed; "ideally only one week, if you have had enough recovery" | `DIR D-31`; `NOTES Plan setup (Chapter 17)` |
| Order of dropping | **Not stated.** Only "skip Support when short" is given. Whether Conditioning goes before Support, and whether Specific may be cut before Base, is not in the skills | |

So the skills give one drop (Support) and one floor (Base at least 6 weeks); the order in which the other
phases go is open ([§9](#9-questions-for-the-user), Q9, Q10).

### 3.3 Micro length: 7, 10 or 14 days

The skills allow 7, 10 or 14 days, set per plan, and say to **ask the athlete, never assume** (`DIR:9`;
`SKILL:82-83`; `NOTES Microcycle`, `NOTES Plan setup`). It changes how many quality sessions, long runs and
recovery weeks fit (`SKILL:83`, citing D-13, D-50, D-55). "Week" in a directive means the microcycle where
the book says per microcycle (`DIR:9`).

How counts scale with the length is only partly said:

| Count | Skills | Source |
|---|---|---|
| Support quality (1 fast, 1 endurance) | Per microcycle, whatever its length ("per microcycle, not per week", user-confirmed). Max 3 quality sessions per microcycle | `DIR D-13`, `D-50`; `NOTES D-50` |
| Support long run | A long run per microcycle (easy, or combined with quality); "2-3 hours or more every two weeks" for experienced runners | `DIR D-50`, `D-55` |
| Base hill sprints | 2-3 sessions "per week" | `DIR D-48` |
| Specific, final 2-3 weeks | 2-3 quality runs "per week" | `DIR D-62` |
| Specific key workouts | 2-4 in the window of days 35-21 (a window of 15 days, not a micro) | `DIR D-60` |
| Long run share | At most 25-30 % of the week's, "microcycle's" running distance | `DIR D-57` |
| Volume jump cycle | 2 weeks at X, a recovery week, 2 weeks higher (in weeks, not micros) | `DIR D-44` |

The user's test of the skill on a 10-day micro (`NOTES Open questions`, points 1 and 2) found that stage
lengths of 42 days do not divide into 10-day micros (the test used 4 micros = 40 days) and that "per week"
and "per microcycle" give different caps (a long run of 27 km per week against 38 km per 10-day micro).

### 3.4 Sessions the athlete sets per micro

The skills treat the number of **run days** as the athlete's own choice, fixed once and kept from Conditioning
through the taper: "run days per week chosen in Conditioning stay constant from Base through Taper"
(`DIR D-41`; `SKILL:86`, "Run days per week (D-40, D-41): the number to hold through the whole
plan"). The skill asks for starting mileage, peak mileage, run days and weekly time and microcycle length, and
"never assumes" them (`SKILL:82-88`). The book gives no number of run days ("high frequency" in Support,
`DIR D-17`; "frequently" in Base, `DIR D-45`). The user's test used 6 run days per 10 days
(`NOTES Open questions, point 3`), which is the athlete's choice, not a book number.

The skills' own counts of *quality* sessions are fixed by phase (§4-§6), not set by the athlete; the athlete
sets how many days are runs, and the rest are easy or recovery runs.

## 4. Phase by phase

### 4.1 Conditioning

For returning after a long break, before Base (`NOTES Conditioning (Chapter 15)`).

| Item | What the skills say | Source |
|---|---|---|
| Session types | **Skills silent.** No session list, no intensity rule. The only content rule is the exit test | `DIR D-40` |
| Hard sessions | Skills silent | |
| Length | No set length; ends when all three hold: target run days per week, at least 50 % of peak volume, no pain | `DIR D-40` |
| Volume | At least 50 % of peak at the end; Base then goes on to at least 80 % of peak | `NOTES Conditioning`; `DIR D-09` |
| Run frequency | The days chosen here stay constant to the taper | `DIR D-41` |
| Mileage progression | The 2-1-2 jump-and-hold cycle (D-44) is for Base and Support, **not Conditioning** | `DIR D-44` |
| Starting mileage for Base | If coming back from injury or surgery, use Conditioning to reach the Base starting mileage first | `NOTES D-42` |

### 4.2 Base

"Before the difficult work of training, get the aerobic system and the neuromuscular system used to high-level
output" (`NOTES Training structure`). Build the two extremes: very easy running and very fast, very short
running (`NOTES P-05`; `SKILL:21`).

| Session type | Count, length and repetitions | Rest and recovery | Intensity / fraction | Hard for placing? | Source |
|---|---|---|---|---|---|
| Easy runs (very easy) | Frequently; weeks 1-2 are easy only | Prioritise sleep/nutrition (not assessable) | Base endurance **80-85 % of race speed**, HR Z1 (proposed) | No | `DIR D-45`, `D-47`; `PACES:18`, `47` |
| Strides | 50-400 m, 100 m most common; quick and relaxed; "usually" at the end of easy or long runs; weeks 1-2 "increasingly more". No count per session or per week | None stated | **Not a percentage of race pace** | Skills silent (they sit inside easy runs) | `DIR D-07`; `D-47`; `NOTES Strides` |
| Hill sprints | Reps **at most 8 s**, all-out (RPE 10) (hard rule). Build to **8 reps of 8 s, 2-3 sessions per week** (guideline; whether 8 reps is a cap is unclear) | Rest between reps **at least 3 min** (hard), 5 min preferred, 10 min optimal; if heart rate or breathing is labored abort or lengthen | All-out, effort-based; the Base (speed) band is 115-120 % of race speed but the skills do not say which sessions use it | Skills silent. The code treats them as hard (§7) | `DIR D-04`, `D-05`, `D-06`, `D-48`; `PACES:12` |
| Fartlek (informal speedwork) | Named as an example of the fast, short extreme; no structure given | None | Skills silent | Skills silent | `DIR D-08`; `NOTES Fartlek` |
| Long run | Added after hill sprints (earlier at high mileage): long for the athlete but easy, **about 2 hours**; built gradually (no run over 110 % of the longest of the last 28 days, not from the book) | | Easy (Z1-2) | Skills silent (long runs "get shorter and faster" over the season, `D-01`) | `DIR D-49`, `D-39`, `D-01` |
| Weighted strength | Begin in Base; no count | | | | `DIR D-46` |

**Volume and intensity mix.** At least **80 % of Base running** at the two extremes (very easy, and very fast
and short: hill sprints, strides, fartlek); at most 20 % anything between (moderate or race-like). Hard
("at least"). The unit is unclear; the skills default to time and say to report the result as an estimate
(`DIR D-08`). Weekly mileage rises through Base and reaches **at least 80 % of peak** by the end
(hard) (`DIR D-09`); it starts at the athlete's starting mileage, held for 4 weeks before
increasing (`NOTES D-42`).

**Hard sessions per micro, and spacing.** Hill sprints 2-3 per week (§3.3); **no spacing rule** for them.
No limit on hard sessions per micro is given for Base.

**Length.** At least 6 weeks (hard), no maximum (`DIR D-03`).

### 4.3 Structural (Support)

"Train to train": get fit enough to do the hard workouts of the next stage (`NOTES Training structure`).
Train the paces on either side of race pace, **never at race pace**.

| Session type | Count / length / repetitions | Rest and recovery | Fraction of race speed (marathon table) | Hard for placing? | Source |
|---|---|---|---|---|---|
| **Fast quality** (speed endurance; intervals) | 1 per micro. Start of Support near 114 %, end near 106 %. Volume (length or number of intervals) rises; no range for a work length | Recoveries get shorter over the stage ("probably", the author's hedge); no value | **106-114 %** (book text 105-115 %), HR Z4 (proposed). Start 114 %, end 106 % | A *quality session* (counts toward the cap of 2, max 3); not called hard | `DIR D-13`, `D-50`, `D-53`; `PACES:14`, `NOTES D-53` |
| **Endurance quality** (muscular endurance) | 1 per micro. Volume rises, pace rises toward 94 %; add distance through intervals, not a longer continuous tempo | Short recoveries (example 20-30 s) | **86-94 %** (book text 85-95 %), HR Z2 (proposed). End near 94 % | A quality session; not called hard | `DIR D-13`, `D-50`, `D-54`; `PACES:19`, `NOTES D-54` |
| **Long run** | One per micro, easy, or combined with a quality session (then it counts as that quality session). 2-3 hours or more every two weeks, for experienced runners (exempt from the 90-minute limit). Or shorten and speed up toward the Specific (endurance) band 95-99 % | | Easy, or the quality band if combined | Skills silent (spaced "like hard" is the code's choice) | `DIR D-50`, `D-55`, `D-56`, `D-16` |
| Easy / recovery runs | The rest; "may and should include strides and short hill sprints" (the 8 s type assumed, to confirm) | | 80-85 % (Z1) | No | `DIR D-58` |
| Other runs | Runs rarely exceed 90 minutes, except the long run and ultra runners | | | | `DIR D-16` |

**Worked examples (the only work lengths in the skills).** These come from NOTES, Chapter 17, and are
examples for one runner, not ranges. The durations are this document's arithmetic from the example paces and
distances (1 mile = 1609.344 m), marked "≈":

| Example | Work and recovery | Work length ≈ | Source |
|---|---|---|---|
| Fast progression, step 1 | 20 × 200 m, 200 m recovery, at 8:20-8:25 per mile | 62 s | `NOTES Support quality workouts` |
| Fast progression, step 2 | 24 × 200 m, 200 m recovery, at 8:30 | 63 s | same |
| Fast progression, step 3 | 2 × (6 × 400 m + 100 m) + 400 m, at 8:34 | 128 s | same |
| Fast progression, step 4 | 3-mile tempo, continuous | ≈ 26 min | same |
| Endurance progression, step 1 | 6 miles continuous at 11:05 | ≈ 66 min | same |
| Endurance progression, step 2 | 6 × 1 mile at 10:50, recoveries 20-30 s | 650 s (10:50) | same |
| Endurance progression, step 3 | 2 × 4 miles at 10:35 | ≈ 42 min | same |
| Endurance progression, step 4 | 30 × 400 m at 10:20 | 154 s | same |
| Long run + endurance quality | A 20 km long run of 3 × 5 km at 94 %, with warm-up, recovery and cool-down | not given (pace not stated) | `NOTES Support quality workouts` |
| Long run + fast quality | 20 km easy plus 6 × 1000 m with recovery | not given | same |

The two progressions use different example runners (fast: a goal near a 4:00 marathon; endurance: near
4:10-4:15, `NOTES`), so they are not one athlete's plan. The fast progression shows the work going from 200 m
repeats to a continuous tempo effort by step 4; the endurance one from a continuous run to 400 m repeats.

**Volume and intensity mix.** At least **80 % of Support mileage at easy pace** (guideline; measure by
distance, also report time) (`DIR D-15`). Faster-than-race and slower-than-race workouts are
equally distributed, not counting easy runs (`DIR D-17`). Weekly volume rises from about **80 % to 100 % of
peak** (peak is the ceiling, hard); the progression is 2 weeks at X, a recovery week, 2 weeks higher
(`DIR D-28/D-51`, `D-44`).

**Hard sessions per micro, and spacing.** **Two quality sessions per micro, at most three**, whatever the
micro length (hard cap); a long run combined with quality counts as one of them (`DIR D-50`).
**Spacing: skills silent.**

**Progression across the stage.** Quality stays inside the two bands but grows in intervals, duration and
distance; "balance an increase in one aspect with a decrease in another", and flag a week where volume, pace
and recovery all get harder (`DIR D-52`). Long runs may instead shorten and speed up (`DIR D-56`).

### 4.4 Specific

"Stop training to train and start training directly for the race" (`NOTES Specific (Chapter 17)`). The
three biggest weeks are 5 to 3 before the race; within three weeks "the money is in the bank".

| Session type | Count / length | Rest and recovery | Fraction of race speed | Hard for placing? | Source |
|---|---|---|---|---|---|
| Race-pace workout | "Not too long or demanding"; no number | | **100 %** (HR Z3 middle, proposed) | A key workout; not called hard | `DIR D-19`; `PACES:16` |
| Slightly faster than race | Focus on increasing volume; no number | | **101-105 %** (Z3 upper half) | Key workout family | `DIR D-20`; `PACES:15` |
| Slower-than-race long run | About 12 s/km (about 20 s/mile) slower than race pace; optionally 1-2 km faster at the end | | **95-99 %** (Z3 lower half) | Long run | `DIR D-21`; `PACES:17` |
| **Alternation run** | A long run: first half easy, building; second half alternates 1 km fast (about 106 %) and 1 km slow (about 95 %). Example: race pace 4:30/km, 30 km: 15 km building to 4:50/km (≈ 93 %), then 15 × alternating 4:15 / 4:45. At most 3 in days 21-56; each after at least one very easy day and several (read as 2 or more) recovery days. Chapter 13 said "once or twice in Specific"; they conflict | "Recovery" km is almost race pace | ≈ 106 % / ≈ 95 % | A key workout; "very hard" | `DIR D-24`, `D-65` |
| **Glycogen depletion run** | 1-2 in Specific; **never within 21 days of the race** (hard); fasted state not in the app | | not given | Key workout | `DIR D-22` |
| **Fast-finish run** | The last 1-10 km significantly faster, maybe the last 300-800 m full effort | | not given | Key workout (a long run) | `DIR D-23` |
| **Special block** | Morning a specific workout, evening a slightly less gruelling one; then up to a week of easy running. At most 1-2 in the whole training period. A large share at 101-103 %. For ultras: back-to-back long runs | | **101-103 %** share | Key workout | `DIR D-25`, `D-26` |
| **Sarcomere run** | Hard downhill. Only 3-5 per cycle, 14-56 days before the race, none in the final 14 days; after at least 6 weeks of strength training. Treadmill downhill ≤ 6 % and ≤ 20 km, or steep downhill repeats, or mountains. The "2-3 weeks to recover" conflicts with 3-5 in six weeks | | effort-based | Key workout | `DIR D-66`, `D-67`, `D-68` |
| **Very long run** | Named as a key workout; **not defined** | | | Key workout | `DIR D-63` |
| Glycogen store run | The day before the race (24-36 h): see §4.5 | | 3-5K pace | | `DIR D-69` |
| Easy / recovery runs | **Very easy** ("easier than ever"); strides allowed; nothing between | | Base endurance 80-85 % (Z1) | No | `DIR D-59` |

**Week shape (hard).** Every running day is a key workout or very easy running; no moderate days; **no
hill-sprint sessions in Specific** (the user resolved D-59 over the casual mention in Chapter 13) (`DIR
D-59`; `NOTES Hill sprints in Specific`).

**Key workouts per micro, and spacing.** 2-4 key workouts in days 35-21 before the race (the three biggest
weeks), "with at least a couple of days between them" (hard) (`DIR D-60`). In the final 2-3 weeks
(days 21-1, with the taper), 2-3 quality runs **per week** at a much lower volume than weeks 5-3, regularly
touching race pace, and the rest slow easy runs with strides (`DIR D-62`). The hardest training
is done 3-4 weeks before the race; no intensity increase in the last 30 days (`DIR D-35`).

**Volume and intensity mix.** **90-100 % of peak** mileage, most miles very easy (the notes give no
percentage; default more than 50 %) (`DIR D-61`). Total volume drops only 10-20 % towards the race,
so quality volume falls much more than the total (`DIR D-62`, `D-32`). Mileage stays level or dips slightly
(`DIR D-11`).

### 4.5 Taper

One week, the stage after Specific (days 1-7) (`DIR D-31`).

| Item | What the skills say | Source |
|---|---|---|
| Volume | Cut only **10-20 %** (taper week = 80-90 % of peak) (hard). Start the week "as if" at about 90 %, drop mileage significantly in the last 3 days; 1-2 days off "if you feel you need it". No step, linear or exponential taper | `DIR D-32`, `D-64`; `NOTES P-13` |
| Frequency and intensity | Do not reduce them (hard); the 1-2 days off are the exception | `DIR D-33` |
| New stressors | None: every workout type must already have appeared (hard) | `DIR D-34` |
| Hardest training | Finished 3-4 weeks before the race; no intensity increase in the last 30 days (hard) | `DIR D-35` |
| Gaps | No more than 72 hours without training (hard) | `DIR D-37` |
| Sleep | Prioritise | `DIR D-36` |
| Session types | The quality types already used, at lower volume: 2-3 quality runs per week touching race pace (final 2-3 weeks), the rest slow easy runs with strides | `DIR D-62` |
| Glycogen store run | 24-36 h before the race: warm-up 1-3 km, a few 100 m strides, **one 90 s interval at 3-5K pace** (about 114-117 % of marathon speed, the notes' estimate), then 400-600 kcal of carbohydrate. A planned exception to D-33/34/35 | `DIR D-69`; `NOTES D-69` |
| Hard for placing | Skills silent | |

## 5. The pace bands, in one place

Fractions of race **speed**, from the Chapter 16 table (`PACES:11-19`); pace = race pace / fraction. The HR
column is the user's own mapping, "not from the book, to calibrate" (`PACES:41-53`); it resolves about three
tiers (easy Z1-2, race effort Z3, hard Z4-5), not seven.

| Band | Fraction of race speed | Used in | HR zone (proposed) |
|---|---|---|---|
| Base (speed) | 1.15-1.20 | Base speed work (which sessions is not stated; hill sprints and strides are effort-based) | Z4 upper to Z5 |
| Support (speed) | 1.06-1.14 (text 1.05-1.15) | Structural fast quality | Z4 |
| Specific (speed) | 1.01-1.05 (special blocks 1.01-1.03) | Specific, slightly faster | Z3 upper half |
| Race pace | 1.00 | Specific | Z3 middle |
| Specific (endurance) | 0.95-0.99 | Specific long runs | Z3 lower half |
| Support (endurance) | 0.86-0.94 (text 0.85-0.95) | Structural endurance quality | Z2 |
| Base (endurance) | 0.80-0.85 | Base, and the very easy days of Specific | Z1 |

Race distance. The table is for **marathon** goal times 2:10-4:15 (`PACES:3-4`). The alternation-run example
is a 30 km run at a 4:30/km race pace (`DIR D-24`); the glycogen store run uses 3-5K pace (`DIR D-69`).
Other distances: the same percentages, flagged as an assumption (`PACES:31-33`). Hilly or ultra races: use
effort, never raw hilly pace (`PACES:35-39`).

## 6. Dials the skills give, summarised

| Dial | Value | Source |
|---|---|---|
| Phases and lengths | Conditioning open; Base ≥ 6 wk; Support 6 wk; Specific 6 wk; Taper 1 wk | §3.1 |
| Hard sessions per micro | Support 2 (max 3) quality; Specific 2-4 key workouts in days 35-21 and 2-3 quality per week in the last weeks; Base 2-3 hill sprints per week; Taper keeps the quality types | §3.3, §4 |
| Spacing | Specific key workouts: at least a couple of days; alternation: ≥ 1 very easy plus several recovery days before. Base, Support: silent | `DIR D-60`, `D-65` |
| Mix | Base ≥ 80 % extremes; Support ≥ 80 % easy; Specific most (default > 50 %) very easy | §4 |
| Volume | Conditioning ends ≥ 50 % of peak; Base ends ≥ 80 %; Support 80 → 100 %; Specific 90-100 %; Taper week 80-90 % | §4 |

## 7. The code today, number by number

The code is `TrainingParadigm.triphasic` and its neighbours in `Sources/TrainingCore`. The paradigm's own
doc comment says only what is settled is encoded; the profiles are MVP5-100's (`TrainingParadigm+BuiltIn.swift`).

### 7.1 `TrainingParadigm.triphasic`

| Field | Code value | Skills | Status |
|---|---|---|---|
| `phases` | conditioning, base, structural, specific, taper | Conditioning, Base, Support, Specific, Taper (`SKILL:22`) | match (Support = structural) |
| `phaseMixes[.conditioning]` | `medium` 0, `high` 0; speed `moderate` 0, `fast` 0, `max` 0; tolerance 0.05 | Skills silent on Conditioning content (§4.1) | skills silent; the code's "easy running only" is a product choice |
| `phaseMixes[.base]` | `medium` 0, `high` 0; speed `moderate` 0, `fast` 0; tolerance 0.05 (slow and `max` unlisted) | At least 80 % at the extremes, at most 20 % anything between; unit unclear (`DIR D-08`) | **differs**: the code allows 0 ± 5 % in `medium`/`high` and `moderate`/`fast`; the skills allow up to 20 % in between. The code also has no ceiling on max-speed time (the skills give none either) |
| `phaseMixes[.structural]`, `[.specific]`, `[.taper]` | none | Support ≥ 80 % easy (distance); Specific most very easy (> 50 % default); Taper: keep intensity | **not modelled** |
| `defaultMix` | `nil` | | |
| `hardIntensity` | `.high` | Skills silent on "hard" | skills silent |
| `hardSpeed` | `.max` (so 8 s sprints are placed like a hard day) | Skills silent; hill sprints "2-3 per week" with full rest between reps | skills silent |
| `spacesLongRunsAsHard` | `true` (set `false` for an ultra by `resolved(for:)`) | Skills silent on long-run spacing; the alternation-run rule (`D-65`) spaces by very easy and recovery days | skills silent; MVP5-138 |
| `minDaysBetweenHardSessions` | 2 (Tuesday to Thursday is 2, so one day between) | Specific key workouts: "at least a couple of days between them" (`D-60`); alternation: ≥ 1 very easy plus several recovery days (`D-65`). Base and Support: silent | **differs or matches, depending on how "a couple of days between" is counted**; Q5 |
| `maxHardSessionsPerMicro` | none (no limit; "the athlete sets") | Support 2 quality, max 3 per micro; Specific 2-4 key workouts in days 35-21, 2-3 per week in the final weeks; Base hill sprints 2-3 per week | **differs / not modelled** (the code has no cap and no phase-specific count) |
| `maxBackToBackLongRunPairsPerMicro` | `[7: 1, 10: 1, 14: 2]` | Special block: back-to-back long runs for ultras, "max 1-2 in the training period" (`D-25`, `D-26`); no per-micro number | **differs** (and belongs to MVP5-138) |
| `shortenablePhase` | `.specific` | Specific is 6 weeks; no rule to shorten it (§3.2) | **skills silent** |
| `sessionProfiles` | empty for every phase | §4 | **not modelled** (this document supplies the input) |
| `guardrailOverrides` | none | Skills silent | |
| `maxLongRunMeters` | 35 000 m (kept only for an ultra) | Skills: long run ≤ 25-30 % of the micro's distance (`D-57`); ~2 h in Base; 2-3 h or more every two weeks in Support | skills use a share, the code a fixed ceiling; MVP5-138 |

The doc comments on the phase constants in `CyclePhase+Triphasic.swift` describe the phases differently
from the skills, and are listed as input for MVP5-137:

| Constant | Code comment | Skills |
|---|---|---|
| `.conditioning` | "easy running only, for returning from illness or injury" | Skills: return after a long break; no content rule |
| `.structural` | "faster easy running and longer, slower sprint-type intervals" | Support: fast quality at 106-114 % (intervals growing to a tempo) and endurance quality at 86-94 %, one each per micro; no race pace; "sprint-type" is Base |
| `.specific` | "running just slower than race pace, intervals just faster" | Race pace itself plus both neighbours (95-99 %, 101-105 %), the key workouts, and very easy days |

### 7.2 Hard sessions: how the skills' sessions land in the code

A session is hard when its intensity category is `high` (a meaningful share of time in zones 4-5) or its
speed level is `max` (the highest zone of a work step, zone 5 or RPE 8+) (`TrainingParadigm.isHard`;
`IntensityCategory`, `SpeedLevel`). With the user's proposed HR mapping:

| Skills session | Zone of the work | Code intensity / speed | Counts as hard in the code? |
|---|---|---|---|
| Hill sprints (8 s, RPE 10) | RPE 10 | `low` / `max` | yes (`hardSpeed`) |
| Support fast quality, 106-114 % | Z4 | `high` / `fast` | yes |
| Support endurance quality, 86-94 % | Z2 | `low` / `slow` | **no** |
| Specific race-pace, 95-99 %, 101-105 % | Z3 | `medium` / `moderate` | **no** |
| Alternation run (106 % / 95 %) | Z3-4 | long run, `medium` or `high` | as a long run (spacing only), or hard if the fast km are Z4 |
| Fast-finish, special block, glycogen depletion, very long run | Z3 | long run or two sessions | long run (spacing only) where tagged `long`; otherwise no |
| Sarcomere run | effort | not modelled (needs gradient) | not modelled |

So the skills' "quality session" and "key workout" are wider than the code's "hard", which matters for the
Support cap of 2-3 and the Specific spacing (Q4).

### 7.3 Session profiles and the template fit (MVP5-118)

`SessionProfile` holds a `SessionType`, an optional `workLength` range in seconds, an optional `workCount`
range and an optional single `raceTargetFraction`. `TemplateFitter` filters library templates on type and on
overlap of the work length and count, then fits parameters to the target duration (`TemplateFitter.swift`).

| Skills | `SessionProfile` can hold it? | Status |
|---|---|---|
| Work length of an interval (seconds) | `workLength` | The slot exists; **the skills give no range**, only examples (§4.3) |
| Work in distance (200 m, 400 m, 1 mile, 1000 m, 1 km) | Only as seconds; the fitter solves a distance step through the pace model | not modelled directly; a distance goal is converted to time |
| Repetition count | `workCount` | Slot exists; skills give 8 reps (hill sprints), 20-30 reps of 200-400 m, 6, 3, 2 reps in the examples |
| Fraction of race speed as a range (1.06-1.14, 0.86-0.94) | One `raceTargetFraction` | **differs**: the skills give a band and a drift inside it (114 % → 106 %; 86 % → 94 %); the profile has one number and no progression of it |
| Progression of the work | `progressedWorkLength` steps the work length from the low to the high end across the micros of a phase | **differs**: the skills' structural fast quality gets *longer volume at slower pace and shorter recovery*; only the work length moves in the code |
| Recovery between reps | Not in the profile (a template parameter at its default) | **not modelled** (the skills: shorter recoveries over Support; hill-sprint rest ≥ 3 min) |
| Strides, fartlek, alternation, fast finish, glycogen depletion, special block, sarcomere, very long run | `SessionType` has `easy, long, interval, tempo, hillRepeats, recovery, race`; the doc says the specifics belong to the template | **not modelled** as types |
| Hard sessions as a profile property | None | not modelled |

Built-in templates against the skills' numbers (`BuiltInWorkoutTemplates.swift`):

| Template | Parameter ranges | Skills |
|---|---|---|
| Base Full-out hill sprints | 8 s fixed, reps 3-12 (default 6), rest 3-15 min (default 5 min); RPE 10 | 8 s (match); reps ≤ 8 target (the range allows 12; `D-48` unclear whether 8 is a cap); rest ≥ 3 min (match), 5 preferred, 10 optimal |
| Short interval run | work 30-120 s, reps 6-12, recovery 60-180 s | The skills' 200 m examples (≈ 62 s) fit the work range, but 20-24 reps and 200 m recovery do not |
| Short interval run (track) | work 50-800 m, reps 6-12, recovery 60-180 s | 200 m and 400 m examples fit per rep; reps 20-30 do not |
| Long Interval Runs | work 3-5 min, reps 3-8 | 1-mile reps (≈ 650 s ≈ 11 min) and 4-mile reps do not fit |
| Cruise Interval Runs | work 5-15 min, reps 3-6 | Closest to the 6 × 1-mile and 2 × 4-mile examples; neither fits |
| Tempo run | 15-45 min | The 3-mile tempo (≈ 26 min) fits |
| Long run | 10-35 km | The skills' ~2 h and 2-3 h runs fit by distance |
| Long run with fast finish / Fast Finish Run | finish 1-4 km, or 5-30 min | Skills: last 1-10 km |
| Long run with speed play (Long Fartlek) | reps 8-20 | Fartlek is named but not specified |

This table says only whether a skill example could be produced; it does not say the library should change.

This PR adds six templates for the notes' structures (zones follow the user's HR mapping; the notes' examples are the defaults): *Alternation Run* (15 km build + 8 × 1 km Z4 / 1 km Z3), *Muscular Endurance Repeats* (reps 2-30, 400 m-6.4 km, recovery 20-60 s; covers 6 × 1 mile, 2 × 4 miles, 30 × 400 m), *Speed Endurance Repeats* (reps 6-30, 200 m-1 km, distance recovery; covers the 200 m and 400 m examples), *Long run with endurance intervals* (3 × 5 km, 20 km), *Long run with speed intervals* (20 km + 6 × 1000 m) and *Glycogen Store Run*. So the rows above for the 20-30 rep examples, the 1-mile and 4-mile reps, the alternation run and the glycogen store run are now producible. Choices the notes do not give are marked in the doc comments (recoveries of the two long runs, easy-first order, the 100 m stride jog). Special blocks (two sessions in a day) and the undefined very long run are not templates.

**Limits of the zone mapping.** (1) *Race distance:* the zones, like the percentages, are marathon-calibrated (§5). Decided (Q19, 2026-10-22): triphasic is marathon-calibrated, and a plan for a shorter target race gets a `CalibrationWarning` on the proposal (MVP5-143: more than 2 % from 42,195 m, not an ultra, a target race given; it does not block the plan); later the same percentages with the zone derived from the resolved pace instead of a fixed template zone. Example, a 20:00 5K (4:00/km): the structural endurance band 0.86-0.94 is 4:15-4:39/km and the base endurance band 0.80-0.85 is 4:42-5:00/km (this document's arithmetic), which is moderate, not very easy, for a 5K runner. (2) *Hard work (resolved in this PR):* `TemplateAnalysis` counted a work step as hard only at zone 3 or higher or RPE 7 or more, so the two Z2 endurance templates had no work length and could not be requested through a `SessionProfile.workLength`. A work step at zone 2 in an interval set (a block repeated by a parameter or more than once, with a recovery step) now counts as hard work; an easy run's Z2 body and the target-less strides do not. Tests pin it, including that the fitter matches *Muscular Endurance Repeats* on a work-length profile.

### 7.4 Step targets (MVP5-122)

`StepTargetResolver.resolve(_:on:athlete:raceTarget:raceTargetFraction:)` turns a profile's fraction into a
pace: pace = race pace / fraction, written as a range of ±2 % (`fractionPaceTolerance`), only when the race
target is a pace; otherwise `.noRaceTarget` or `.unsupportedRaceTarget`. A work step with a heart-rate zone
keeps the zone and takes the phase pace as its companion if the pace falls in the zone's pace range, else
`.paceOutsideZone`.

| Skills | Code | Status |
|---|---|---|
| Fraction of race **speed** (pace ÷ fraction) | Same direction | **match** |
| A band per session type (106-114 %, 86-94 %, 101-105 %, 95-99 %, 115-120 %) | One fraction per profile | **differs** (a band collapses to one number) |
| Drift within the stage (114 % → 106 %, 86 % → 94 %) | None | **not modelled** |
| Effort, not pace, on hilly or ultra courses | `.unsupportedRaceTarget` for a non-pace target | consistent with `PACES:35-39`; the zone mapping is the user's own |
| Which HR zone each band lives in (Z1, Z2, Z3 thirds, Z4, Z5) | Zones come from the template; the resolver checks the phase pace lies in the zone | A template whose work zone is not the band's zone reports `.paceOutsideZone`. Z3 holds three bands (95-99, 100, 101-105 %), so one zone cannot tell them apart |

### 7.5 Short-lead-time compromises (MVP5-115)

`LeadTimeCompromiser.adjust` counts whole micros (`leadTimeDays / microLengthDays`). While the macro is
longer it (1) drops `conditioning`, (2) drops `structural`, (3) shortens `shortenablePhase` (`specific` for
triphasic) to `minimumShortenedMicros` (1 by default), (4) trims the oldest remaining blocks; the taper
(`taper`, `race`) is never cut, and a lead time below taper plus the minimum throws. Conditioning is in the
plan only if `PlanPreferences.includeConditioning` is true (default false).

| Skills | Code | Status |
|---|---|---|
| Conditioning optional, skipped when already running | Dropped first; only in the plan if `includeConditioning` | **match** in effect; the skills give a test (athlete not running regularly) the preference stands in for |
| Support (structural) can be skipped when short on time (read as under about 13 weeks) | Dropped second, but **only when the whole macro is longer than the lead time**, not at a 13-week threshold | **differs** in trigger: the skills tie the skip to "short on time"; the code ties it to the macro not fitting |
| Base at least 6 weeks (hard) | Oldest blocks trimmed last with **no 6-week floor** | **differs** |
| Specific 6 weeks; no rule to shorten | Shortened before Base is trimmed, down to 1 micro | **skills silent**; a 1-micro Specific is far below 6 weeks |
| Taper one week | Never cut, but counted in whole micros of the chosen length | **differs** for 10- and 14-day micros: a taper of one micro is 10 or 14 days, not 1 week (Q8) |
| Order of dropping | conditioning → structural → shorten specific → trim oldest | **skills silent** on everything after Support |

### 7.6 Layout, volume and micro length

| Skills | Code | Status |
|---|---|---|
| Structural and Specific are 6 weeks each | Phase lengths are `MacroTemplate` micro counts the caller gives; **no triphasic `MacroTemplate` is built in** (`CycleLayoutBuilder` recognises only `.taper` and `.race` by name) | **not modelled** |
| 6 weeks in 7-, 10- and 14-day micros | 7 d: 6 micros; 14 d: 3 micros; 10 d: 4.2 (the code counts whole micros) | **not modelled**; Q7 |
| Taper week 80-90 % of peak, starting near 90 %, dropping in the last 3 days | `VolumeCurveBuilder`: taper micros step from **0.7** to **0.5** of peak, race micro **0.3** | **differs** (the skills cut only 10-20 %) |
| Base end ≥ 80 % of peak; Support 80 → 100 %; Specific 90-100 % | `VolumeCurveBuilder` climbs in equal steps from the starting volume to the peak at the last build micro; recovery micros 0.6 of the previous build; no phase-specific holds | **not modelled** (no hold at 90-100 % through Specific; the peak is reached at the last build micro, which for triphasic would be in Specific) |
| 2 weeks at X, a recovery week, 2 weeks higher | `MesocycleTemplate` build/recovery pattern, `recoveryLoadFraction` 0.6, `buildLoadStep` 0.08 | pattern exists; the skills give no recovery-week size or step size (`D-44`), so 0.6 and 0.08 are **skills silent** |
| Run days constant from Conditioning to taper | Run days live in `RunAvailability`, independent of the paradigm | **match** in spirit |
| Athlete sets micro length | `microLengthDays` is a layout and compromise input (7, 10, 14) | **match** |
| Athlete sets sessions per micro | `RunAvailability` (days, slots, run types, runs per day) | **match** |

## 8. Differences, as input for MVP5-137 and MVP5-138

For **MVP5-137** (dial in the triphasic numbers):

1. **Base mix.** The code forbids `medium`/`high` and `moderate`/`fast` (0 ± 5 %); the skills allow up to
   20 % in between (hard "at least 80 %" at the extremes, unit unclear). Decide the share and the unit.
2. **Structural, Specific and Taper mixes** have no target. The skills give: Support at least 80 % easy
   (distance); Specific most miles very easy (default > 50 %); nothing for the taper but "keep intensity".
3. **Hard definition.** Support endurance quality and the Specific Z3 workouts are not hard in the code,
   though they are the skills' quality sessions and key workouts. Whether `hardIntensity` or the sessions'
   classification should change is a decision for MVP5-137.
4. **Hard sessions per micro.** The code has no limit; the skills cap Support quality at 2 (max 3) per micro
   and set 2-4 key workouts in days 35-21.
5. **Spacing.** The code has 2 days everywhere; the skills give a spacing only for Specific key workouts and
   alternation runs. How "a couple of days between" is counted is open (Q5).
6. **Profiles.** None are set; the skills give bands and examples but no work-length or repetition ranges.
7. **Band versus single fraction**, and **drift inside a stage**, are not modelled by `SessionProfile`.
8. **Phase comments** in `CyclePhase+Triphasic.swift` differ from the skills' description of each stage.
9. **Volume curve:** the taper (0.7 → 0.5, race 0.3) cuts far more than the skills' 10-20 %; Specific holds
   90-100 % in the skills and the curve does not.
10. **Lead time:** no 6-week floor on Base; Specific shortened below its 6 weeks; a taper counted in micros.

For **MVP5-138** (ultra): the skills mention ultras in four places, none with a number: Support runs may
exceed 90 minutes for ultra runners (`DIR D-16`), special blocks for ultras are back-to-back long runs
(`DIR D-25`), race pace on hills and ultras is ill-defined and effort should be used (`PACES:35-39`), and the
user's own test of an ultra plan lists ten open points (`NOTES Open questions`, "Test of the skill on a 73 km
ultra plan": long run per week versus per microcycle, 6 run days per 10 days at a 90 km peak, no ultra
effort anchor, a taper at 80-90 % before a 73 km race, and long runs in Specific against D-59). The code's
`maxBackToBackLongRunPairsPerMicro` and `maxLongRunMeters` have no counterpart in the skills.

## 9. Questions for the user

One row per open point. "Blocks" says what each one blocks: **this document** (the description), **137** (the
numbers), or **138** (ultra). Each gives the skills, the code and the options, with an example.

| # | Point | Skills say | Code has | Options | Blocks |
|---|---|---|---|---|---|
| Q1 | **Work-length ranges for Structural fast and endurance quality** | Only examples: fast 200 m (≈ 62 s) → 400 m (≈ 128 s) → a 3-mile tempo; endurance 6 mi → 6 × 1 mi (650 s) → 2 × 4 mi → 30 × 400 m (≈ 154 s) (`NOTES Chapter 17`) | `sessionProfiles` empty; `workLength` is one range for the whole phase, progressed linearly | (a) Take the ranges from the examples: fast 60-130 s then continuous, endurance 150-2600 s; (b) one range for the phase, e.g. fast 60-180 s and endurance 150-650 s; (c) you give the ranges | 137 |
| Q2 | **Race-target fractions: one number or a band?** | A band per stage, drifting: fast 114 % → 106 %, endurance 86 % → 94 % | One `raceTargetFraction` per profile; no drift | (a) The mid-point (fast 1.10, endurance 0.90); (b) start and end values interpolated across the micros; (c) a range stored on the profile | 137 |
| Q3 | **Specific: work lengths and the race-pace share** | "Not too long or demanding", "focus on volume"; no numbers for race-pace or 101-105 % work. Fast-finish last 1-10 km; alternation 1 km; special block share 101-103 % | Nothing | You give ranges, or the generator plans only the key workouts that have numbers (alternation, fast finish, long run 12 s/km slower) | 137 |
| Q4 | **Which sessions are "hard" for placing days?** | Quality session (Support), key workout (Specific), hill-sprint session (Base). Not called hard | Hard = `high` intensity or `max` speed; long runs spaced like hard | (a) Keep the code's rule; the Support endurance quality and Specific workouts are not hard; (b) count every quality session and key workout as hard; (c) per phase | 137 |
| Q5 | **What does "a couple of days between key workouts" mean?** | "At least a couple of days between them for recovery" (`D-60`); alternation: ≥ 1 very easy day and several recovery days before (`D-65`, read as ≥ 2) | `minDaysBetweenHardSessions` 2, where Tuesday to Thursday is 2 (one day between) | (a) 2 days between (Tue → Fri), so the value is 3 in the code's counting; (b) keep 2 (Tue → Thu); (c) 3 for alternation runs only | 137 |
| Q6 | **Base: unit and share of the "extremes"** | "At least 80 %" at the extremes; unit unclear, default time (`D-08`) | `medium` and `high` at 0 ± 0.05 | (a) Share of time, up to 20 % between; (b) share of distance; (c) keep 0 and note the difference | 137 |
| Q7 | **A 6-week phase on a 10-day micro** | 6 weeks = 42 days | Whole micros only: 7 d → 6, 14 d → 3, 10 d → 4 (40 d) or 5 (50 d) | (a) Round to 4 micros (40 d); (b) round to 5; (c) allow a shorter last micro; (d) offer 7 and 14 only | 137 |
| Q8 | **The taper is 1 week; a micro is 7, 10 or 14 days** | Taper 1 week (up to 3 allowed) | The taper is whole micros | (a) A taper micro of the chosen length (10 or 14 days); (b) always the last 7 days, the rest of that micro as Specific; (c) a shorter final micro | 137 |
| Q9 | **Order in which phases are dropped** | Only "skip Support when short"; Base ≥ 6 weeks; Specific 6 weeks; Conditioning optional | Conditioning, Structural, shorten Specific (to 1 micro), trim oldest | (a) Keep the code's order but stop at Base 6 weeks; (b) never shorten Specific, cut Base to its 6 weeks first; (c) your order | 137 |
| Q10 | **"Short on time" for skipping Support** | Under about 13 weeks to the race (the skill's reading; the notes ask what the book means) | Dropped when the macro does not fit | (a) Drop Structural when under 13 weeks; (b) keep the code's trigger | 137 |
| Q11 | **Hard sessions per micro for 7, 10, 14 days** | Support 2 (max 3) quality **per micro** whatever the length; hill sprints 2-3 **per week**; final weeks 2-3 per week | No limit | (a) Support 2 per micro for all lengths; (b) scale with the length (2 / 3 / 4, as polarized); (c) as (a) for Support, per-week counts scaled by days/7 for hill sprints and the final weeks | 137 |
| Q12 | **Long run: per week or per micro** | At most 25-30 % of "the week's (microcycle's)" distance | A fixed ceiling in meters for ultras | Per micro or per 7 days (the user's ultra test found 38 km against 27 km) | 137/138 |
| Q13 | **Conditioning content** | Silent; only the exit test | Easy only, no `moderate`/`fast`/`max` | (a) Keep easy only (a product choice); (b) allow strides | 137 |
| Q14 | **Volume curve by phase** | Base ≥ 80 %, Support 80 → 100 %, Specific 90-100 %, taper week 80-90 % of peak | One ramp to the peak at the last build micro; taper 0.7 → 0.5; race 0.3 | Change `VolumeCurveBuilder` for triphasic, or accept the difference | 137 |
| Q15 | **Session types missing** | Strides, fartlek, alternation, fast finish, glycogen depletion, special block, sarcomere, very long run | `SessionType` is small on purpose; specifics are in the templates | Match them to templates and tags, or add types (you asked for nothing to be added without a request, so none are proposed here) | 137 |
| Q16 | **Hill-sprint count** | Build to 8 × 8 s; unclear if 8 is a cap | Template range 3-12 reps | (a) Cap at 8; (b) keep 3-12 | 137 |
| Q17 | **Support "short hill sprints" on easy days** | "May and should", 8 s type assumed; you earlier assumed longer ones in Support | Not modelled | Which length applies | 137 |
| Q18 | **Ultra** | Silent except effort anchor, back-to-back long runs in special blocks, Support runs over 90 minutes | `maxBackToBackLongRunPairsPerMicro` `[7:1, 10:1, 14:2]`, `maxLongRunMeters` 35 km | Left to MVP5-138 | 138 |
| Q19 | **Other race distances** | The percentages and zones come from the marathon table; for other distances the skills apply the same percentages and call it an assumption (`PACES:31-33`). A 20:00 5K puts the endurance band at 4:15-4:39/km and base endurance at 4:42-5:00/km | `StepTargetResolver` divides the race pace by the fraction; the template zone is fixed, so a 5K gives `.paceOutsideZone` | **Decided 2026-10-22: (a)** marathon-calibrated; the plan proposal warns for another target distance (MVP5-143: `TrainingParadigm.calibratedDistanceMeters` = 42,195 for triphasic, `PlanProposal.calibrationWarning`, race outside ±2 % of it and not an ultra; no race, no warning). Later: (b) same percentages, zone derived from the pace. (c) distance-specific bands if you give them | 143 |
| Q20 | **Pace targets instead of heart-rate zones** | The skills give bands as % of race speed; the zone mapping is yours | Steps carry a zone, with the phase pace as the companion target; a work step with no target and a fraction gets a pace target. Z2 interval work is hard work for `TemplateAnalysis` since this PR (option c, done) | (a) one template, plus a choice of primary target (heart rate or pace) when the steps are resolved; (b) a second set of templates with pace targets | 137 |

**Questions that block this document:** none. Every point above is listed here and not decided, and the
description of the skills in §3-§5 stands without an answer. The ones that most shape MVP5-137 are Q1 and Q2
(profile numbers), Q4 (what is hard) and Q7-Q9 (phase lengths and dropping).

## 10. The numbers as decided (MVP5-137)

Decided with the user on **2026-10-22**, one question per number. Each is a data value in `TrainingParadigm.triphasic`, using the existing `IntensityMix`; no rule was added. A mix lists target ± tolerance, so "at most 20 %" is 0.10 ± 0.10. Categories are checked separately. The evaluator counts a session's whole planned time under its one intensity and speed level, so a hill-sprint session counts entirely as `speed.max`.

| Number | Old | New | Reason |
|---|---|---|---|
| Base `medium`, `high`, `moderate`, `fast` | 0 ± 0.05 | **unchanged** (decided) | User: at least 95 % at the two extremes, very easy or very fast and short (skills: at least 80 %, `DIR D-08`; Q6) |
| Base ceiling on `max` time | none | **none** (decided) | Skills give none; sprints are a few seconds of a session |
| Structural intensity | none | `high` 0.10, `medium` 0, ±0.10 | Skills: at least 80 % easy, never race pace (`DIR D-15`, `D-17`); suggestion accepted. **Question 3 got no separate answer: confirm** |
| Structural speed | none | `fast` 0.10, `moderate` 0, ±0.10; `max` unlisted | Fast quality is Z4; sprints on easy days allowed (`DIR D-58`); user answered A |
| Specific intensity and speed | none | `medium`, `high`, `moderate`, `fast` each 0.25 ± 0.25 (none above 50 %) | Skills: most miles very easy, default more than 50 % (`DIR D-61`); user answered A |
| Taper intensity and speed | none | same as specific | Skills only say to keep intensity (`DIR D-33`, `D-62`); user answered A |
| Tolerance | 0.05 | 0.05 where a target is exact (conditioning, base); 0.10 structural; 0.25 specific and taper | The tolerance sets the width of the "at most" ranges |
| `minDaysBetweenHardSessions` | 2 | **3**, then **2** (2026-10-27) | MVP5-137 read "a couple of days between" literally (Tue to Fri). Changed back after the first real plan: with Tuesday and Thursday as the only hard days a 3 left a hard session out of most micros. One easy day in between is the default; 3 is for the very intense specific workouts (alternation run), which ask for it themselves since MVP5-147 (`RecoveryDays`: 1 before and 3 after). The plan can ask for another value (`PlanPreferences.minDaysBetweenHardSessions`) |
| `maxHardSessionsPerMicro` | none | **none** (decided) | Skills cap quality sessions, not the code's "hard" |
| `hardIntensity`, `hardSpeed` | `.high`, `.max` | **unchanged** (decided) | |

### Triphasic plan quality (2026-10-27)

Decided with the user after the first real plan, written into `TrainingParadigm.triphasic.sessionProfiles` (no other number is set):

| Profile | Decided |
|---|---|
| Base | Hill sprints (`hillRepeats`), work at most 8 s (`DIR D-04`) |
| Structural fast quality | Q1 (a): work length 60 s growing to 130 s over the phase; Q2 (b): 114 % of race speed drifting to 106 % across the micros |
| Structural endurance quality | Q1 (a): 150 s growing to 2600 s; Q2 (b): 86 % drifting to 94 % |
| Specific and taper | Asks for race-pace work (100 %), when a template's zone can hold that pace (the fitter does not check it yet: the step keeps its zone target and is not reported); only that; the work lengths and the share of race pace (Q3) and the 101-105 % band are not set |

A micro's hard runs take the phase's hard profiles in turn (starting at the micro's position in its phase, so a micro with a single hard run alternates between them), so a structural micro with two hard runs gets a fast and an endurance quality session. The number of hard sessions per micro is the athlete's; the request defaults to 2 for a 7-day micro, 3 for 10 days and 4 for 14. The number of repetitions is not decided here: the template fitter takes it from the micro's volume, so the hard session grows and the easy runs and the long run give way. Q5 is answered as (b) with the alternation run (c) done in MVP5-147: every workout template can carry the days it wants free before and after it (`RecoveryDays`, below), and the alternation run wants 1 before and 3 after (`D-65`: at least one very easy day before and several recovery days after).

### Recovery days per template (MVP5-147)

`WorkoutTemplate.recoveryDays` (`RecoveryDays(before:after:)`, optional) is the number of days a workout wants free of other demanding workouts before and after it, counted like the spacing (Tuesday to Thursday is 2). For an earlier workout A and a later one B the days between them should be at least `A.after + B.before`. Defaults when a template sets none: interval, tempo and hill sessions want 0 before and the paradigm's spacing after (2 for triphasic, or the plan's `minDaysBetweenHardSessions`); a long run the same where the paradigm spaces long runs like hard sessions (not for an ultra, which allows back-to-back long runs); easy runs, recovery runs and untagged templates want nothing and neither need recovery nor block the days next to them. The alternation run sets 1 and 3 itself. The numbers are minimums to aim for: the generator refits a run without the template that wants more days than its neighbours leave, and when no other template fits it keeps the workout and reports `PlanCompromise.recoveryDaysShort`. The assigner treats the days a workout of the micro before wants as soft too. A special block, which may break the rule, is not modelled yet; a template can ask for less.

Not decided here (still open in §9): the specific work lengths and race-pace share (Q3), phase lengths and dropping (Q7-Q10), the volume curve (Q14), conditioning content (Q13).
