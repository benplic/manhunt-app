# Overnight build handoff — 2026-11-18 (America/New_York)

Branch: `cursor/playtest-wave1-2a9d` @ `b959686`

## Status: Waves 1–4 landed. No PR opened.

### Server
- `pytest -q`: **173 collected path** — full suite typically **170–173 passed**; a few tests (`test_live_join_code_is_unique_and_reusable_after_end`, `test_demo_view_and_all_host_actions`, `test_keep_replica_awake_pings_while_a_lobby_exists`) flake under load but **pass in isolation**. Re-run before trusting a red.
- `ruff check .`: clean.

### Wave summary
1. **Persist race** — per-game lock, `last_persisted_seq`, ON CONFLICT, drain after commit, idempotent end.
2. **Spawn lock** — 2-tick in-spawn streak; clock re-holds on leave; no reveals in head_start.
3. **Map dupes** — empty Annotation titles; one pin per player; spawn zone dedupe.
4. **Kick** — `removed` envelope + 4403; lobby broadcast; client home via `onRemoved`.
5. **Rename / hiccup** — re-auth on name change; `/v1/me` restore; debounce hiccup toast.
6. **SF Symbols** on power dock; **README Horizon** (CTF, Senior assassin, Persistent).
7. **Confirms** — leave hunt / sign out.
8. **Rematch** — `POST /v1/games/{id}/rematch` → new lobby.
9. **Ping toggles** — sound + flashlight opt-in (default off).
10. **Tracker** — forbidden in hot_cold / persistent; hint UX copy.
11. **Zones** — hide spawn after head start; lockdown fade; `safe_remove_after`; `scan_radius_m` / `scan_count`.
12. **New powers** — rescue, create_safe, move_safe, shrink_now (+ SF Symbols).

### Open TODOs / concerns
- Dock UI pickers for **rescue** (target player) and **move_safe** (zone + point) still TODO; create_safe reuses map drop.
- Polygon safe zones cannot use move_safe (clear error).
- Stash `stash@{0}: overnight-wip-before-w1f-merge` may hold pre-build local WIP (docker-compose, ArenaGeometry, AppSettings, FakeGameService, AppStore, playtest.log) — review before dropping.
- Username compliance / moderation: skipped (needs Scott).
- Do not merge/PR/deploy until Scott asks.

### Worktrees (safe to prune)
`manhunt-w1a`…`w1f`, `w1c`, `w1d`, `w2a`, `w2b`, `w3a`…`w3c`, `w4` under `/Users/benny/`.
