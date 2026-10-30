# Plans for the 5k, 10k and half marathon (MVP5-152)

**Status (2026-10-29): the user confirmed the sessions below (specific and structural), one paradigm that chooses its
profile set from the race distance, and the phase-intensity steps.** The phase-intensity steps are built (MVP5-153);
the profiles per distance are the next step (MVP5-154). The user asked on 2026-10-29 for plans for these three
distances, and chose that the session content is drafted here and corrected before it is built. The content below is my summary of common coaching practice, not a quotation of a source: no
book, plan or course is cited because none was given. Every number is a starting point to confirm or change.
Where the user already decided something, it is marked *decided*.

## 1. Why it is needed

`TrainingParadigm.triphasic` takes its percentages and zone mapping from a marathon table, so a plan for a shorter
race gets bands that are too moderate and a `CalibrationWarning` (MVP5-143, decided Q19 on 2026-10-22).
`TrainingParadigm.polarized8020` has no distance-specific sessions. So today a 5k, 10k or half marathon plan has
no session content of its own.

## 2. What the code can express

A paradigm has, per phase (conditioning, base, structural, specific, taper), a list of `SessionProfile`s: a session
type (`interval`, `tempo`, `hillRepeats`, `long`, `easy`, `recovery`), an optional work length range (seconds), an
optional work count range, and a fraction of race speed that can drift across the phase
(`raceTargetFraction` to `endRaceTargetFraction`; above 1 is faster than race pace). The athlete sets the number of
hard sessions and long runs per micro; the paradigm sets the minimum days between hard sessions (2 for triphasic).
The fitter takes the templates whose work lengths fit the profile.

Two things proposed here are not in the code yet, and are separate decisions:

- **Phase-intensity steps** (*decided 2026-10-29, built in MVP5-153*). A hard step of a template has no fixed
  zone: it is "work at this phase's intensity". The plan works out the pace from the race pace and the fraction,
  finds where that pace sits in the athlete's zones (a zone position, MVP5-148), and writes it as the target
  and as the heart rate when the workout is sent. The same template then fits a 5k and a marathon: 86 % of a
  marathon pace is an easy zone, 86 % of a 5k pace is a threshold zone. The zone check of MVP5-150 stays for
  templates with a fixed zone.
- **Profiles per distance class** (*decided 2026-10-29: one paradigm*). One paradigm chooses its profile set from the target race, the way
  `resolved(for:)` already does for an ultra. The classes proposed: 5k and 10k share the structure (they differ in
  the lengths and the fractions); the half marathon is its own; the marathon and ultra stay as they are.

The work lengths below are written in minutes or metres. A profile holds seconds, so a distance is converted at the
race pace of the athlete (1000 m at 3:50/km is 230 s).

## 3. The sessions per distance (draft)

**Which phase has race-pace work.** Only the specific phase and the taper work at race pace (fraction about 1.00),
as in the triphasic paradigm. The structural phase works either side of it: below race pace for endurance quality
and threshold (fraction under 1.00 for the 5k and 10k, a little over 1.00 for the half marathon, where threshold
pace is faster than half-marathon pace), and above it for fast quality (1.04 to 1.10). The base phase has no race-pace
work. The tables say the phase of every row.

Fractions are of the race speed of that distance. The recovery between repetitions is not in a profile today (a
template parameter at its default); it is written here so the templates can be checked.

### 3.1 5 km

The race is run near the top of the aerobic range, so the specific work is intervals at and just above race pace and
the structural work builds the threshold under it.

| Phase | Session | Work | Count | Fraction | Recovery | Note |
|---|---|---|---|---|---|---|
| Base | Hill sprints | 8 s, all out | 6 to 10 | RPE 10 | 3 min or more | as triphasic base |
| Base | Strides, easy volume, long run | | | | | no hard session |
| Structural | Threshold (cruise intervals) | 6 to 12 min | 3 to 5 | 0.92 to 0.95 | 1 to 2 min jog | grows in length |
| Structural | Fast quality | 200 to 400 m | 8 to 14 | 1.05 to 1.10 | equal jog, shorter over the phase | |
| Specific | Race-pace intervals | 1000 to 1200 m (3 to 4 min) | 4 to 6 | 1.00 to 1.03 | 2 to 3 min jog | the key session |
| Specific | Fast quality | 400 m | 10 to 12 | 1.03 to 1.06 | 60 to 90 s | |
| Taper | One race-pace session, short | 1000 m | 3 to 4 | 1.00 | 2 min | volume cut about 40 % |

Hard sessions per 7-day micro: 2, plus the long run. Long run: easy, 60 to 90 min.

### 3.2 10 km

| Phase | Session | Work | Count | Fraction | Recovery | Note |
|---|---|---|---|---|---|---|
| Base | Hill sprints, strides, easy volume | as 5k | | | | |
| Structural | Threshold | 8 to 15 min | 2 to 4 | 0.95 to 0.98 | 1 to 2 min | or one 20 to 30 min tempo |
| Structural | Fast quality | 400 to 1000 m | 6 to 10 | 1.04 to 1.08 | 60 to 120 s | |
| Specific | Race-pace intervals | 1600 to 2400 m (6 to 9 min) | 3 to 5 | 1.00 to 1.02 | 2 to 3 min jog | the key session |
| Specific | Threshold maintenance | 10 to 15 min | 2 | 0.97 | 2 min | |
| Taper | One race-pace session, short | 1600 m | 2 to 3 | 1.00 | 2 min | volume cut about 35 % |

Hard sessions per micro: 2, plus the long run, 75 to 105 min, easy.

### 3.3 Half marathon

| Phase | Session | Work | Count | Fraction | Recovery | Note |
|---|---|---|---|---|---|---|
| Base | Hill sprints, strides, easy volume | as 5k | | | | |
| Structural | Tempo / threshold | 15 to 40 min continuous, or 3 x 10 min | 1 | 1.02 to 1.05 | 2 min if split | grows in length; above race pace, not at it |
| Structural | Fast quality | 800 to 1200 m | 5 to 8 | 1.06 to 1.10 | 90 s | |
| Specific | Race-pace blocks | 3 to 5 km | 2 to 3 | 1.00 | 2 to 3 min | the key session |
| Specific | Long run with fast finish | last 4 to 8 km | 1 | 1.00 | | the marathon's, shorter |
| Taper | One race-pace session, short | 2 km | 2 | 1.00 | 2 min | volume cut about 30 % |

Hard sessions per micro: 2, plus the long run, 90 to 135 min.

### 3.4 Marathon (*decided 2026-10-29*, for reference)

The specific phase asks for a fast finish that grows from the last 3 km to the last 10 km at race pace
(the Run Elite notes give 1 to 10 km); the alternation run stays a separate, rarer session. Written in km, so the
fast-finish template should take km, or the profile converts at the race pace (3 km at 4:30/km is 13.5 min).

## 4. The same for every distance

- The phases and their order are the triphasic ones (conditioning, base, structural, specific, taper). The macro
  is shortened by the existing lead-time compromises, so a 10-week plan to a 5k drops conditioning first.
- Two hard sessions per micro and a minimum of 2 days between them (triphasic default); the athlete can change both.
- Recovery micros, TSB aims, strain and the other guardrails are the plan generator's, unchanged.
- The tapers are shorter than the marathon's: one micro.

## 5. What I am least sure of

1. The **fractions**. They are placed from the rule of thumb that threshold pace is about 10k to half-marathon pace
   and 5k pace is a little above, and they will land in different zones for different athletes.
2. **Whether the half marathon and 10k want two hard sessions** in the base and structural phases, or one and a
   steady run.
3. **The lengths of the taper** for the 5k (one micro of 7 days may be too long or too short).
4. **Whether 5k and 10k are the same class** with different lengths, or two classes.

## 6. Decisions (2026-10-29)

1. The key sessions are right: specific-phase race-pace work (5k 4 to 6 x 1000 to 1200 m, 10k 3 to 5 x 1600 to 2400 m,
   half 2 to 3 x 3 to 5 km) and the structural sessions of section 3 (below and above race pace).
2. One paradigm, with the profile set chosen by the race distance, as `resolved(for:)` does for an ultra.
3. Phase-intensity steps, so the templates do not fix a zone.

Open: the points of section 5 stay open until the plans can be looked at; they are starting numbers, not decisions.
