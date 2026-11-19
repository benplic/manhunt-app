# Horizon 4 — Ranked / Public Lobbies

> **Status:** Long-term horizon. Not scheduled. **Last of the four horizon goals** — open only after Capture the Flag, Senior assassin, and Long-distance persistent have designs (and preferably shipped slices) and Scott explicitly prioritizes public play.  
> **Order:** 4 of 4 horizon goals.

**Goal:** Strangers can find each other: public lobbies, optional ranked matchmaking, and fair-ish skill separation — without turning the friends park MVP into a toxic open internet product prematurely.

**Architecture:** Matchmaking and lobby discovery **in front of** existing `GameSession` create/join. Private join codes stay. Public path adds queue → allocated game → same engine presets (Classic first; CTF/assassin/persistent only if those horizons already exist). Trust, moderation, and identity (Sign in with Apple) are prerequisites, not afterthoughts.

**Tech stack:** Same stack + Azure-scale hosting (Phase 2), APNs, likely a matchmaking worker or queue table. No Rust rewrite for this.

## Product sketch

- **Public lobbies:** browse or quick-join open Classic (later CTF) games with region / party-size filters.
- **Ranked:** optional ladder; MMR or simple W/L; party size caps; season resets.
- Host tools: kick, report, undo tag already from earlier phases; public adds report reasons and enforcement.
- Default: friends private codes remain first-class; public is opt-in from a separate entry point (“Find a hunt”), not the home screen default.

## Likely work

- `lobbies` / `matchmaking` service: queue, region, preset, party fill, timeout.
- Ranked ratings table; anti-smurf / smurf soft gates later.
- Username moderation, block/report (called out as needing Scott in overnight handoff — blocks public launch).
- Rate limits, join flood control, abuse of create-empty-lobby.
- iOS: Find a hunt flow distinct from Enter code / Host.

## Dependencies (must exist first)

1. Horizon 1–3 designs at minimum (so public does not invent three modes under matchmaking pressure).
2. Phase 2: Apple Sign-In, Azure (or equivalent always-on), crash recovery, APNs.
3. Explicit moderation policy and tooling (human Scott sign-off — security/legal adjacent).
4. Stable Classic park UX so public players are not debugging MVP bugs.

## Why last

Public strangers amplify every incomplete rule, lag complaint, and moderation gap. Shipping CTF, assassin, and persistent first proves modes and presence models with trusted cohorts. Ranked/public is distribution and trust infrastructure on top — not the next park feature.

## Out of scope for this horizon doc

- Cross-play with Android.
- Spectating / Twitch integration.
- Paid battle pass.
- Full TDD task list until this goal is opened.

## Open questions (resolve in a design spec before coding)

1. Region = geo IP, self-reported city, or arena proximity only?
2. Ranked only Classic, or every mode gets a ladder?
3. Age gate / school-only pools for assassin-like modes?
4. What is the first enforcement action on report (mute, ban, human review)?

## Acceptance (when eventually built)

- [ ] Quick-join fills a Classic lobby to start size without a shared code.
- [ ] Ranked rating updates only on completed ranked games; pytest covers edge cases (disconnect, abandon).
- [ ] Report → enforceable action path documented and tested at API level.
- [ ] Closed in remaining-benchmarks with commit hash + test names; human gate for first public playtest.

## Related

- README Horizon list (ordered; this item is last).
- Design when opened: `docs/superpowers/specs/YYYY-MM-DD-ranked-public-lobbies-design.md` (not written yet).
