# Horizon 2 — Senior Assassin

> **Status:** Long-term horizon. Not scheduled. Do not implement until Capture the Flag has a design pass and Scott opens this goal.  
> **Order:** 2 of 4 horizon goals (after CTF, before Persistent and Ranked/public).

**Goal:** A longer-cycle elimination game for a cohort (class year, club, friend group): each player has a target, tags eliminate or reassign, and the game runs over days or weeks rather than one park session.

**Architecture:** Stretch the session model beyond a single continuous tick loop. Prefer **campaign / season** state in Postgres with intermittent presence, not a multi-week always-on 1 Hz tick. Reuse tag claim (QR / UWB), pairing range, and event log; add target assignment, kill confirmation, and dormancy rules.

**Tech stack:** Same stack. Expect APNs (Phase 2.8) and durable session recovery (Phase 2.4) before this is playable for real.

## Product sketch

- Cohort joins one season; server assigns a ring or graph of targets (classic assassin: you hunt A, someone hunts you).
- Elimination via the same tag pipeline when both are nearby (QR primary; UWB optional).
- On a successful tag: victim out (or becomes spectator); assassin inherits victim’s target (ring rule) — **default lean:** ring inheritance.
- Optional safe hours / campus zones where tags are blocked (honor-system zones first; geo-enforced later).
- Leaderboard: eliminations, survival time, not Classic points economy unless reused carefully.

## Likely engine / product work

- `assassin_targets` module or season service: assignment, inheritance, deadlock detection.
- Season status distinct from park `lobby|head_start|active|paused|ended` — e.g. `season_open`, `season_closed`.
- Idle cost: no 1 Hz tick while nobody is ranging; wake on location / tag / schedule.
- Proof: photo or QR token already covers “I was there”; avoid requiring always-on GPS trail for days (PII + battery).
- Moderation hooks: dispute a kill, host/admin undo (builds on Phase 2.6 undo tag).

## Dependencies (must exist first)

- Phase 2 crash recovery + persisted sensitive location policy (or an explicit “no trail” assassin mode).
- APNs for “your target is nearby” / season events (optional but expected).
- CTF horizon design lessons on teams/objectives if assassin ever adds team seasons.

## Out of scope for this horizon doc

- Public ranked assassin ladders (that is Horizon 4).
- Weapon / dart hardware integrations.
- Full TDD task list until this goal is opened.

## Open questions (resolve in a design spec before coding)

1. Ring vs free-for-all vs assigned pairs that reset each week?
2. Safe zones: schedule-only, geo polygons, or both?
3. How long can someone go dark before auto-forfeit?
4. University / org admin role vs single host?

## Acceptance (when eventually built)

- [ ] Season create / join / assign targets; ring inheritance on tag covered by pytest.
- [ ] No continuous 1 Hz tick while the season is idle.
- [ ] Cohort playtest (≥6 people, ≥3 days): at least two real eliminations and one dispute/undo.
- [ ] Closed in remaining-benchmarks with commit hash + test names.

## Related

- README Horizon list (ordered).
- Design when opened: `docs/superpowers/specs/YYYY-MM-DD-senior-assassin-design.md` (not written yet).
