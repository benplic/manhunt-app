# Horizon 1 — Capture the Flag

> **Status:** Long-term horizon. Not scheduled. Do not implement until Classic park MVP is stable and Scott opens this goal.  
> **Order:** 1 of 4 horizon goals (before Senior assassin, Persistent, Ranked/public).

**Goal:** A park-scale objective mode where teams race to take and return flags instead of (or in addition to) eliminating every hider.

**Architecture:** New preset composed of existing modules plus CTF-specific modules (flag carriers, capture zones, team win). Server stays authoritative; iOS renders flag pins and carrier state from filtered `PlayerView`. Reuse arena polygons for bases / capture pads rather than inventing a second geometry store.

**Tech stack:** Same as roadmap (FastAPI engine modules, SwiftUI MapKit). No new languages.

## Product sketch

- Two (or more) teams; each has a home base and one or more flags.
- Seeker/hider roles may map to attackers/defenders per half, or stay free-for-all with team scoring — **default lean:** fixed teams, any teammate can carry, opposite team tags drop the flag.
- Win: score N captures, or most captures when the timer ends.
- Tagging a carrier drops the flag at drop point (or returns it home — decide in the design pass).
- Safe zones / power-ups: decide per-preset which Classic tools stay (Shield, Scan) vs which break CTF (Ghost while carrying).

## Likely engine work

- `flag_policy` module: flag entities, pickup radius, drop/return rules, carrier visibility.
- `team_roles` or extend `roles`: team id on `PlayerState`, win checks by team score.
- Arena snapshot: named zones `TEAM_A_BASE`, `TEAM_B_BASE`, optional mid flags.
- Events: `flag_picked_up`, `flag_dropped`, `flag_captured`, `flag_returned`.
- Views: everyone sees flag pins; carrier precise location only under the same reveal/OOB rules as Classic (do not invent a second privacy model).

## Dependencies (must exist first)

- Stable Classic preset, park playtest, crash recovery if hosted beyond home (Phase 2).
- Schema-driven presets (Phase 5.1–5.2) so CTF settings do not hard-code a new iOS form.

## Out of scope for this horizon doc

- Ranked matchmaking, cross-city play, spectator streams.
- Full TDD task list — write that only when this goal is opened.

## Open questions (resolve in a design spec before coding)

1. Drop-in-place vs return-on-tag?
2. Can the carrier use power-ups?
3. One flag per team or neutral mid flags?
4. Does head start still apply, or do both teams release together?

## Acceptance (when eventually built)

- [ ] Preset `capture_the_flag` loads; arena validation requires two team bases.
- [ ] Pickup / drop / capture / return are server-authoritative with pytest coverage.
- [ ] Park playtest: two teams of ≥2 complete at least one capture and one drop-on-tag.
- [ ] Closed in remaining-benchmarks with commit hash + test names.

## Related

- README Horizon list (ordered).
- Design when opened: `docs/superpowers/specs/YYYY-MM-DD-capture-the-flag-design.md` (not written yet).
