# Overnight build handoff — 2026-11-18 (America/New_York)

Branch: `cursor/playtest-wave1-2a9d` (tip after consolidation commit)

## Status: Waves 1–4 landed. Open items closed. No PR opened.

### Server
- `pytest -q`: **173 passed**, `ruff check .` clean (re-run before trusting a one-off red; a few tests flake under load).

### Closed since morning note
- Rescue + Move-safe dock pickers (confirmationDialogs + map drop).
- `converted_from_hider` on player view for Rescue targets.
- Stash `overnight-wip-before-w1f-merge` folded (compose/AppSettings/ArenaGeometry) then dropped.
- Lane worktrees `/Users/benny/manhunt-w*` removed; lane branches deleted.

### Still out of scope
- Username compliance / moderation (needs Scott).
- Do not merge/PR/deploy until Scott asks.
- Unrelated local branches (`demo-lobby`, `scoring-zones`, etc.) left alone — not part of this playtest wave.
