# Horizon 3 — Long-Distance Persistent Games

> **Status:** Long-term horizon. Not scheduled. Do not implement until Senior assassin’s presence model is sketched and Scott opens this goal.  
> **Order:** 3 of 4 horizon goals (after CTF and Senior assassin, before Ranked/public).

**Goal:** Friends-at-a-distance (e.g. college) play a slow hunt: intermittent location pings, denser clues near frequent places (campus quad, favorite coffee shop), without requiring everyone in one park.

**Architecture:** Persistent **presence + clue** layer on top of (or beside) Classic sessions. Low-frequency location samples, place-affinity hints, and long-lived game state in Postgres. Not a second-by-second park tick across cities. Privacy is the hard constraint: field-level encryption, purge, and need-to-see (Phase 2.3) before any multi-day trail exists.

**Tech stack:** Same stack; likely PostGIS or equivalent place indexing when spatial queries appear (roadmap currently defers PostGIS until needed). APNs for ping / clue notifications.

## Product sketch

- Game lasts days–weeks; players are often cities apart or on the same campus asynchronously.
- Default location mode: rare precise or fuzzy pulses on an interval the host sets (hours, not seconds).
- **Place density:** near saved frequent places, pulse interval shortens and/or hot-cold / fuzzy clues get sharper — “denser near the coffee shop.”
- Optional “check-in” at a place for points or reveals without continuous tracking.
- Win conditions: last uncaught, score threshold, or season timer — pick in design; **default lean:** survival + optional score, not park CTF.

## Likely engine / product work

- `presence_policy` module: pulse interval, accuracy gates, place-boosted intervals.
- `frequent_places`: player- or host-defined geofences (coffee shop, dorm hub) with boost rules.
- Separate from Classic reveal `persistence` timed/persistent pins — naming must stay clear in UI (“long game” vs “pin does not expire”).
- Battery and cellular: background location budgets; never log raw coordinates.
- Views: seekers get fuzzed/clue data only; no continuous live map of every friend.

## Dependencies (must exist first)

- Phase 2.3 encrypted trails + purge + access logging (non-negotiable for multi-day location).
- Phase 2.4 recovery so a long game survives deploys.
- Senior assassin idle/wake patterns (shared “not always ticking” runtime).
- Clear product copy so “Persistent” reveal timing in Classic is not confused with this mode.

## Out of scope for this horizon doc

- Public discovery of strangers’ locations (Horizon 4 / never without explicit consent design).
- Always-on Find My style sharing.
- Full TDD task list until this goal is opened.

## Open questions (resolve in a design spec before coding)

1. One shared map for the friend group, or pairwise hunter/hunted like assassin?
2. Who defines frequent places — each player privately, or host-curated arena places?
3. Minimum pulse interval allowed (abuse / stalking risk)?
4. Does tagging still require physical proximity, or are there remote “claim” rules?

## Acceptance (when eventually built)

- [ ] Long game survives process restart with encrypted presence history and purge job.
- [ ] Place-boosted pulses change interval inside a geofence; pytest covers the schedule math.
- [ ] Friend-group playtest (≥2 cities or ≥2 campus hubs, ≥5 days) with no coordinate leaks in logs.
- [ ] Closed in remaining-benchmarks with commit hash + test names.

## Related

- README Horizon list (ordered).
- Classic reveal “persistent” pins: scoring-zones design — different concept; do not merge names in UI.
- Design when opened: `docs/superpowers/specs/YYYY-MM-DD-persistent-long-distance-design.md` (not written yet).
