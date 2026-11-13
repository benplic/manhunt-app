# Scoring, zones, rules, and live HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deal a seeker count, rank matches by points earned, give fuzzy reveals their own colors and names, and shorten the live status bar to a single pause indicator.

**Architecture:** The engine keeps two counters and one grant function. Reveal settings stay on module id `reveal_fuzzy`; hot/cold reads those settings. The preset editor hides the master switch on locked schema cards. The map draws reveals in a separate layer from safe zones. The live HUD is a layout change only.

**Tech Stack:** FastAPI and pytest on the server. SwiftUI and XCTest on iOS. Module schema from `server/app/schemas/modules.py`, copied to `ios/Manhunt/OfflineModuleSchema.json`.

## Global Constraints

- Distances use 111,320 m per degree, not haversine.
- The engine does not call `datetime.now()` or the global `random`. Use `session.clock` and `session.rng`.
- `ArenaEditorModel` is not `@MainActor`.
- `is_decoy` never goes out on the wire.
- Code, comments, and docs are English. Unfinished behavior gets a `TODO:` comment. Do not swallow exceptions.
- No secrets, coordinates, or tokens in logs.
- Spec: `docs/superpowers/specs/2026-11-13-scoring-zones-hud-design.md`. Do not mark a roadmap bullet done. This work is not a remaining-benchmarks acceptance line.
- Server check: `cd server && . .venv/bin/activate && pytest -q && ruff check .`
- iOS check, when the 18.4 simulator is installed: `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`

---

### Task 1: Seeker count

**Files:**
- Modify: `server/app/engine/session.py` (`assign_roles_random`)
- Modify: `server/app/engine/recovery.py` (`roles_random` branch)
- Modify: `server/app/games/service.py` (randomize body and demo auto-assign)
- Modify: `server/app/schemas/modules.py` (roles field)
- Modify: `server/app/presets/classic.py`
- Modify: `server/tests/engine/test_roles.py`
- Modify: `ios/Manhunt/Domain/RoleAssigner.swift`
- Modify: `ios/Manhunt/LobbyView.swift`
- Modify: `ios/Manhunt/Store/AppStore.swift`
- Modify: `ios/Manhunt/Networking/GameService.swift`
- Modify: `ios/Manhunt/Networking/LiveGameService.swift`
- Modify: `ios/Manhunt/Networking/FakeGameService.swift`
- Modify: `ios/Manhunt/Networking/APIClient.swift` (`RoleRandomBody`)
- Modify: `ios/ManhuntTests/GameRulesTests.swift`
- Test: `server/tests/engine/test_roles.py`

**Interfaces:**
- Consumes: existing `GameSession.add_player` and `_note_input`.
- Produces: `assign_roles_random(seeker_count: int)` logs `{"seeker_count": n}`. `assign_hiders_random(hider_count: int)` logs `{"hider_count": n}` and is only for old inputs. Lobby JSON key `seeker_count`.

- [ ] **Step 1: Write the failing test**

Replace `server/tests/engine/test_roles.py` with:

```python
from uuid import uuid4

from tests.engine.helpers import make_session


def test_random_roles_honor_seeker_count_and_empty_input() -> None:
    session, _ = make_session(seed=99)
    ids = [uuid4() for _ in range(4)]
    for i, player_id in enumerate(ids):
        session.add_player(player_id, f"P{i}", is_host=i == 0)
    session.assign_roles_random(1)
    roles = [p.role for p in session.state.players.values()]
    assert roles.count("seeker") == 1
    assert roles.count("hider") == 3
    assert session.state.inputs[-1]["payload"] == {"seeker_count": 1}

    session.assign_roles_random(0)
    assert all(p.role == "hider" for p in session.state.players.values())

    session.assign_roles_random(90)
    assert all(p.role == "seeker" for p in session.state.players.values())

    empty, _ = make_session(seed=1)
    empty.assign_roles_random(2)
    assert empty.state.players == {}


def test_legacy_hider_count_input_still_deals_hiders() -> None:
    session, _ = make_session(seed=99)
    ids = [uuid4() for _ in range(4)]
    for i, player_id in enumerate(ids):
        session.add_player(player_id, f"P{i}", is_host=i == 0)
    session.assign_hiders_random(1)
    roles = [p.role for p in session.state.players.values()]
    assert roles.count("hider") == 1
    assert roles.count("seeker") == 3
    assert session.state.inputs[-1]["payload"] == {"hider_count": 1}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_roles.py -q`

Expected: FAIL because `assign_roles_random` still deals hiders and `assign_hiders_random` does not exist.

- [ ] **Step 3: Implement**

In `server/app/engine/session.py`, replace `assign_roles_random` with both methods:

```python
def assign_roles_random(self, seeker_count: int) -> None:
    shuffled = list(self.state.players)
    self.rng.shuffle(shuffled)
    seekers = max(0, min(seeker_count, len(shuffled)))
    for index, player_id in enumerate(shuffled):
        self.state.players[player_id].role = "seeker" if index < seekers else "hider"
    self._note_input("roles_random", {"seeker_count": seekers})

def assign_hiders_random(self, hider_count: int) -> None:
    """Replay path for inputs logged before seeker_count existed."""
    shuffled = list(self.state.players)
    self.rng.shuffle(shuffled)
    hiders = max(0, min(hider_count, len(shuffled)))
    for index, player_id in enumerate(shuffled):
        self.state.players[player_id].role = "hider" if index < hiders else "seeker"
    self._note_input("roles_random", {"hider_count": hiders})
```

In `server/app/engine/recovery.py`, replace the `roles_random` branch:

```python
elif kind == "roles_random":
    if "seeker_count" in payload:
        session.assign_roles_random(int(payload["seeker_count"]))
    else:
        session.assign_hiders_random(int(payload.get("hider_count", 1)))
```

In `server/app/games/service.py` `set_roles`, when `mode == "random"`:

```python
roles_body = body
if "seeker_count" in roles_body:
    game.assign_roles_random(int(roles_body.get("seeker_count", 1)))
elif "hider_count" in roles_body:
    game.assign_hiders_random(int(roles_body.get("hider_count", 1)))
else:
    game.assign_roles_random(1)
```

Replace the demo auto-assign block that currently reads `hider_count` and calls `assign_roles_random` (`server/app/games/service.py`, the sample-game setup):

```python
roles = preset.get("modules", {}).get("roles", {})
player_count = len(game.state.players)
if player_count >= 2:
    if "seeker_count" in roles:
        seekers = max(1, min(int(roles["seeker_count"]), player_count - 1))
        game.assign_roles_random(seekers)
    else:
        hiders = max(1, min(int(roles.get("hider_count", 1)), player_count - 1))
        game.assign_hiders_random(hiders)
```

In `server/app/schemas/modules.py` roles block, replace `hider_count` with:

```python
"field_order": ["mode", "seeker_count"],
"fields": {
    "mode": _enum("Assignment", ["random", "manual"], "random", ["Random", "Manual"]),
    "seeker_count": _int("Seekers", 1, 20, 1),
},
```

In `server/app/presets/classic.py`:

```python
"roles": {"mode": "random", "seeker_count": 1},
```

And in `RANGES`, replace the hider tuple:

```python
("roles", "seeker_count"): (1, 20),
```

Update `server/tests/api/test_auth_and_games.py` so the randomize JSON sends `"seeker_count": 1` instead of `"hider_count": 1`. Assert the resulting role counts match one seeker if that test checks counts. If it only checks HTTP 200, the key change is enough.

iOS `RoleAssigner.assign` parameter becomes `seekerCount`. The first `seekerCount` shuffled ids are `.seeker`, the rest `.hider`. Update `GameRulesTests` call sites and expectations: `seekerCount: 1` on four ids yields 1 seeker and 3 hiders; `0` yields all hiders; `90` yields all seekers.

Rename `AppStore.hiderCount` to `seekerCount` (default 1). Thread `seekerCount` through `GameService`, `LiveGameService`, `FakeGameService`, and `RoleRandomBody` (`case seekerCount = "seeker_count"`). `LobbyView` stepper label is `Seekers \(store.seekerCount)`. The footnote reads `Tap a player to cycle Hider, Seeker, and Open. Randomize uses the seeker count above. Everyone else hides.`

`FakeGameService.randomizeRolesSync` must deal seekers with the same rule as the server: first N of its shuffled list are seekers. Match the existing shuffle so tests that only check counts still pass.

- [ ] **Step 4: Run tests**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_roles.py tests/api/test_auth_and_games.py -q && ruff check app/engine/session.py app/engine/recovery.py app/games/service.py app/schemas/modules.py app/presets/classic.py`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/app/engine/session.py server/app/engine/recovery.py server/app/games/service.py server/app/schemas/modules.py server/app/presets/classic.py server/tests/engine/test_roles.py server/tests/api/test_auth_and_games.py ios/Manhunt/Domain/RoleAssigner.swift ios/Manhunt/LobbyView.swift ios/Manhunt/Store/AppStore.swift ios/Manhunt/Networking/GameService.swift ios/Manhunt/Networking/LiveGameService.swift ios/Manhunt/Networking/FakeGameService.swift ios/Manhunt/Networking/APIClient.swift ios/ManhuntTests/GameRulesTests.swift
git commit -m "fix: randomize roles by seeker count"
```

---

### Task 2: Start at 0 and rank by points earned

**Files:**
- Modify: `server/app/engine/state.py` (`PlayerState.points`)
- Modify: `server/app/engine/modules/points.py`
- Modify: `server/app/engine/modules/tag_policy.py`
- Modify: `server/app/demo/controls.py` (`_add_points`)
- Modify: `server/app/engine/views.py`
- Modify: `server/tests/engine/test_points.py`
- Modify: `server/tests/engine/test_tag.py`
- Modify: `ios/Manhunt/Networking/DTOs.swift`
- Modify: `ios/Manhunt/VisualModels.swift`
- Modify: `ios/Manhunt/Store/AppStore.swift`
- Modify: `ios/Manhunt/Networking/FakeGameService.swift`
- Modify: `ios/Manhunt/LiveGameView.swift` (`LeaderboardSheet`)
- Modify: `ios/Manhunt/ResultsView.swift`

**Interfaces:**
- Consumes: `PlayerState` from Task 1's session (no signature change).
- Produces: `grant_points(player, amount: int) -> None`. View fields `points` (spendable) and `points_earned` on `you` and each player. iOS `VisualPlayer.earned`.

- [ ] **Step 1: Write the failing test**

Append to `server/tests/engine/test_points.py`:

`test_points.py` already imports `two_player_hunt`. Add `meters` and `reading` to that import, and import `CATALOG` inside the test.

```python
def test_new_players_start_at_zero_and_spending_does_not_change_earned() -> None:
    from app.engine.modules.power_ups import CATALOG

    session, clock, hider, seeker = two_player_hunt()
    assert session.state.players[hider].points == 0
    assert session.state.players[hider].points_earned == 0
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 100), clock))
    session.taunt(hider)
    earned = session.state.players[hider].points_earned
    balance = session.state.players[hider].points
    assert earned == balance
    assert earned >= 5
    cost = int(CATALOG["ghost"]["cost"])
    session.state.players[hider].points = cost
    session.purchase(hider, "ghost")
    assert session.state.players[hider].points == 0
    assert session.state.players[hider].points_earned == earned
```

`test_ghost_skips_the_next_reveal` buys ghost without setting a balance. After the 0 start that purchase is refused. Before the purchase, set `session.state.players[hider].points = 100`.

In `server/tests/engine/test_tag.py` change `assert session.state.players[seeker].points == 125` to:

```python
assert session.state.players[seeker].points == 25
assert session.state.players[seeker].points_earned == 25
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_points.py tests/engine/test_tag.py -q`

Expected: FAIL on `points == 0` or a missing `points_earned`, and on `125`.

- [ ] **Step 3: Implement**

`PlayerState` in `server/app/engine/state.py`:

```python
points: int = 0
points_earned: int = 0
```

Add to `server/app/engine/modules/points.py`:

```python
def grant_points(player, amount: int) -> None:
    gained = int(amount)
    if gained <= 0:
        return
    player.points += gained
    player.points_earned += gained
```

Replace every `hider.points += ...` and `player.points += points` inside `points.py` with `grant_points(...)`. In `tag_policy.py` replace `seeker.points += 25` with:

```python
from app.engine.modules.points import grant_points

bonus = int(s.module_settings("points").get("tag_points", 25))
grant_points(seeker, bonus)
```

In `server/app/demo/controls.py` `_add_points`, replace `player.points += amount` with `grant_points(player, amount)`.

In `server/app/engine/views.py`, add `"points_earned": player.points_earned` on each player dict and `"points_earned": viewer.points_earned` on `you`. Keep `"points"` as the spendable balance.

iOS:

- `YouDTO` and `PlayerDTO` gain `pointsEarned: Int?` with coding key `points_earned`. Default nil so an older payload still decodes.
- `VisualPlayer` gains `var earned: Int`.
- `AppStore` player mapping sets `earned` from `pointsEarned ?? points`, and `shownPoints` is `match?.snapshot.you.points ?? 0`.
- `FakeGameService` initial `points` is 0. Add `pointsEarned` beside it, and every `points +=` also adds to `pointsEarned`.
- `LeaderboardSheet` sorts and prints `earned`. `ResultsView.ranked` sorts by `earned` and prints `earned`.

The dock keeps `store.shownPoints` (spendable).

- [ ] **Step 4: Run tests**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_points.py tests/engine/test_tag.py tests/engine/test_power_ups.py tests/engine/test_recovery.py -q && ruff check app/engine/modules/points.py app/engine/modules/tag_policy.py app/engine/state.py app/engine/views.py app/demo/controls.py`

Expected: PASS. Recovery rebuilds both counters because grants and purchases replay through the same functions.

- [ ] **Step 5: Commit**

```bash
git add server/app/engine/state.py server/app/engine/modules/points.py server/app/engine/modules/tag_policy.py server/app/demo/controls.py server/app/engine/views.py server/tests/engine/test_points.py server/tests/engine/test_tag.py ios/Manhunt/Networking/DTOs.swift ios/Manhunt/VisualModels.swift ios/Manhunt/Store/AppStore.swift ios/Manhunt/Networking/FakeGameService.swift ios/Manhunt/LiveGameView.swift ios/Manhunt/ResultsView.swift
git commit -m "fix: rank by points earned and start at zero"
```

---

### Task 3: Taunt can be turned off

**Files:**
- Modify: `server/app/schemas/modules.py` (points fields)
- Modify: `server/app/presets/classic.py`
- Modify: `server/app/engine/modules/points.py` (`apply_taunt`)
- Modify: `server/app/engine/views.py` (`taunt_enabled` on `you`)
- Modify: `server/tests/engine/test_points.py`
- Modify: `ios/Manhunt/Networking/DTOs.swift`
- Modify: `ios/Manhunt/LiveGameView.swift` (hide the button)

**Interfaces:**
- Consumes: `grant_points` from Task 2. Points settings dict.
- Produces: `you.taunt_enabled: bool`. `apply_taunt` raises `GameRuleError(ErrorCode.WRONG_PHASE, "Taunts are off.")` when the setting is false.

- [ ] **Step 1: Write the failing test**

Append to `server/tests/engine/test_points.py`:

```python
def test_taunt_disabled_rejects_and_awards_nothing() -> None:
    session, clock, hider, seeker = two_player_hunt({"points": {"taunt_enabled": False}})
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(110, 100), clock))
    with pytest.raises(GameRuleError) as exc:
        session.taunt(hider)
    assert exc.value.code == ErrorCode.WRONG_PHASE
    assert session.state.players[hider].points == 0
    assert session.state.players[hider].points_earned == 0
```

Add `pytest`, `GameRuleError`, and `ErrorCode` imports if the file does not have them.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_points.py::test_taunt_disabled_rejects_and_awards_nothing -q`

Expected: FAIL because the taunt is accepted.

- [ ] **Step 3: Implement**

At the start of `apply_taunt`:

```python
if not bool(s.module_settings("points").get("taunt_enabled", True)):
    raise GameRuleError(ErrorCode.WRONG_PHASE, "Taunts are off.")
```

Points schema `field_order` becomes `["taunt_enabled", "taunt_cooldown"]` with `"taunt_enabled": _bool("Taunt", True)`. Do not add an `enabled` key on the points module. Classic `points` gains `"taunt_enabled": True`.

`views.py` `you` gains `"taunt_enabled": bool(session.module_settings("points").get("taunt_enabled", True))`.

`YouDTO` gains `var tauntEnabled: Bool? = nil` key `taunt_enabled`. In `LiveGameView` the hider Taunt button is inside `if store.match?.snapshot.you.tauntEnabled != false` so a missing key (older server) still shows the button.

- [ ] **Step 4: Run tests**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_points.py -q && ruff check app/engine/modules/points.py app/engine/views.py app/schemas/modules.py app/presets/classic.py`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/app/schemas/modules.py server/app/presets/classic.py server/app/engine/modules/points.py server/app/engine/views.py server/tests/engine/test_points.py ios/Manhunt/Networking/DTOs.swift ios/Manhunt/LiveGameView.swift
git commit -m "feat: let the host turn taunts off"
```

---

### Task 4: Reveal modes

**Files:**
- Modify: `server/app/schemas/modules.py` (`reveal_fuzzy`, drop `hot_cold` from `SCHEMAS`)
- Modify: `server/app/presets/classic.py`
- Modify: `server/app/engine/modules/reveal_fuzzy.py`
- Modify: `server/app/engine/modules/hot_cold.py`
- Modify: `server/app/engine/state.py` (`hint_until_s` on `PlayerState`)
- Modify: `server/app/engine/views.py` (reveal `display_name`)
- Modify: `server/app/demo/controls.py` (`_force_reveal` must not require `enabled`)
- Modify: `server/tests/engine/test_reveal.py`
- Modify: `server/tests/api/test_modules_and_invite.py` (drop `hot_cold` from the required id set)

**Interfaces:**
- Consumes: `RevealPin`, `offset_m`, `session.rng`, `session.module_settings`.
- Produces: reveal settings keys `location_mode` (`fuzzy`|`precise`|`hot_cold`), `persistence` (`timed`|`persistent`), `interval`, `display`, `fuzz`, `hints_enabled`, `hints_persistence`, `hints_interval`. Reveal JSON gains `display_name`. `HotColdModule` reads mode and hint keys from `reveal_fuzzy` when present.

- [ ] **Step 1: Write the failing tests**

Append to `server/tests/engine/test_reveal.py`:

```python
def test_precise_persistent_pin_has_no_radius_and_does_not_expire() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "reveal_fuzzy": {
                "location_mode": "precise",
                "persistence": "persistent",
                "interval": 2,
                "display": 5,
                "fuzz": 40,
            },
            "signal_loss": {"silence": 60},
        }
    )
    hid = uuid4()
    seek = uuid4()
    session.add_player(hid, "Riley", True)
    session.add_player(seek, "Jordan", False)
    session.set_role(hid, "hider")
    session.set_role(seek, "seeker")
    session.start()
    session.record_location(hid, reading(meters(40, 40), clock))
    run_for(session, clock, 2)
    pin = session.state.reveals[0]
    assert pin.radius_m == 0
    assert pin.lat == session.state.players[hid].location.point.lat
    run_for(session, clock, 30)
    assert len(session.state.reveals) == 1
    assert session.state.reveals[0].player_id == hid


def test_timed_hints_clear_after_the_display_window() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "reveal_fuzzy": {
                "location_mode": "fuzzy",
                "persistence": "timed",
                "interval": 2,
                "display": 2,
                "fuzz": 0,
                "hints_enabled": True,
                "hints_persistence": "timed",
                "hints_interval": 5,
            },
            "signal_loss": {"silence": 60},
        }
    )
    hid = uuid4()
    seek = uuid4()
    session.add_player(hid, "Riley", True)
    session.add_player(seek, "Jordan", False)
    session.set_role(hid, "hider")
    session.set_role(seek, "seeker")
    session.start()
    session.record_location(hid, reading(meters(40, 40), clock))
    session.record_location(seek, reading(meters(80, 40), clock))
    run_for(session, clock, 2)
    assert session.state.players[seek].hint is not None
    run_for(session, clock, 2)
    assert session.state.players[seek].hint is None


def test_hot_cold_mode_publishes_hints_without_pins() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "reveal_fuzzy": {
                "location_mode": "hot_cold",
                "persistence": "timed",
                "interval": 2,
                "display": 5,
                "fuzz": 30,
                "hints_enabled": False,
                "hints_persistence": "persistent",
                "hints_interval": 2,
            },
            "signal_loss": {"silence": 60},
        }
    )
    hid = uuid4()
    seek = uuid4()
    session.add_player(hid, "Riley", True)
    session.add_player(seek, "Jordan", False)
    session.set_role(hid, "hider")
    session.set_role(seek, "seeker")
    session.start()
    session.record_location(hid, reading(meters(40, 40), clock))
    session.record_location(seek, reading(meters(80, 40), clock))
    run_for(session, clock, 2)
    assert session.state.reveals == []
    assert session.state.players[seek].hint is not None
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_reveal.py -q`

Expected: FAIL. Today's module expires pins and does not publish hints; `hot_cold` mode is unknown.

- [ ] **Step 3: Implement**

Schema for `reveal_fuzzy` (title `Reveal`, blurb `Location pulses and hot/cold hints.`, add `"locked": True` at the module dict's top level next to `title`). Location is a three-way segmented control like Tag method:

```python
"field_order": [
    "location_mode",
    "persistence",
    "interval",
    "display",
    "fuzz",
    "hints_enabled",
    "hints_persistence",
    "hints_interval",
],
"fields": {
    "location_mode": _enum(
        "Location",
        ["fuzzy", "precise", "hot_cold"],
        "fuzzy",
        ["Fuzzy", "Precise", "Hot/cold"],
    ),
    "persistence": _enum("Location timing", ["timed", "persistent"], "timed", ["Timed", "Persistent"]),
    "interval": _int("Every", 20, 600, 60, step=10, suffix="s"),
    "display": _int("Stays up", 5, 60, 10, step=5, suffix="s"),
    "fuzz": _int("Fuzz", 0, 100, 30, step=5, suffix="m"),
    "hints_enabled": _bool("Hints", True),
    "hints_persistence": _enum(
        "Hints timing", ["timed", "persistent"], "persistent", ["Timed", "Persistent"]
    ),
    "hints_interval": _int("Hints every", 2, 30, 5, suffix="s"),
},
```

Remove the `hot_cold` entry from `SCHEMAS`. Keep `HotColdModule` in `MODULE_TYPES`.

Classic `reveal_fuzzy`:

```python
"reveal_fuzzy": {
    "location_mode": "fuzzy",
    "persistence": "timed",
    "interval": 60,
    "display": 10,
    "fuzz": 30,
    "hints_enabled": True,
    "hints_persistence": "persistent",
    "hints_interval": 5,
},
```

Keep `"hot_cold": {"enabled": True, "interval": 5}` in `CLASSIC_MODULES` so the module still loads. Keep `("hot_cold", "interval"): (2, 30)` in `RANGES`. Add `("reveal_fuzzy", "hints_interval"): (2, 30)`. Leave the existing `interval`, `display`, and `fuzz` ranges. Do not edit `server/tests/engine/test_hot_cold.py`: classic persistent hints at 5 seconds match those assertions, and `refresh_hints` uses `hints_interval` from `reveal_fuzzy` when that key is present.

`PlayerState` gains `hint_until_s: int | None = None`.

`RevealFuzzyModule.on_tick`:

- Do not return early on `enabled`.
- Drop expired pins only when building the live list. A pin with `expires_at_game_s` greater than `game_elapsed_s + 60 * 60 * 24` is persistent; still drop pins whose expiry has passed.
- When `location_mode == "hot_cold"`: clear location pins, do not create new ones, and let hints run via `refresh_hints` / `HotColdModule` (hints are always on in this mode).
- On a location pulse (Fuzzy or Precise), delete existing reveals for that `player_id` before appending.
- `location_mode == "precise"`: pin at the true point, `radius_m = 0`.
- `location_mode == "fuzzy"`: keep the seeded offset. `radius_m` is `fuzz` (0 is allowed and the client treats 0 as precise).
- Timed expiry is `game_elapsed_s + display`. Persistent expiry is `game_elapsed_s + 60 * 60 * 24 * 365`.
- Hints are active when `location_mode == "hot_cold"`, or when `location_mode == "fuzzy"` and `hints_enabled` is true. Precise never publishes hints.
- If hints are active and `hints_persistence == "timed"`, set `seeker.hint_until_s = game_elapsed_s + display` for every seeker on that pulse (Fuzzy timed location pulse, or Hot/cold timed refresh). Classic order has `hot_cold` before `points` and after `win`, while `reveal_fuzzy` is earlier, so hot/cold runs **before** reveal in the same tick. Call `publish_hints` at the end of a timed-hints pulse so the same second publishes:

```python
def publish_hints(s: GameSession) -> None:
    from app.engine.modules.hot_cold import refresh_hints
    refresh_hints(s)
```

Call `publish_hints` at the end of a timed-hints pulse. `HotColdModule.on_tick` calls the same `refresh_hints`.

`refresh_hints` rules:

- Read settings from `s.module_settings("reveal_fuzzy")` when `location_mode` or `hints_enabled` is in that dict, else from `self.settings` / `s.module_settings("hot_cold")`.
- Hints active when mode is `hot_cold`, or mode is `fuzzy` with `hints_enabled` true (default true when key missing on fuzzy). Mode `precise` clears hints.
- Disabled, jammed, or phase not `active`: set `hint` and `hint_until_s` to None.
- Persistent: existing interval refresh (`hints_interval`).
- Timed: if `hint_until_s` is None or `game_elapsed_s > hint_until_s`, set `hint` to None. If a pulse just set `hint_until_s` and `hint` is None, compute `_hint_for`.

`views.py` reveal dict adds `"display_name": state.players[pin.player_id].display_name` when that player exists.

`_force_reveal` drops the `enabled` check. It still requires the module to be loaded. When mode is `hot_cold`, force-reveal is a no-op for pins (or temporarily pulses fuzzy for demo — keep it as forcing a pin pulse only when mode is fuzzy or precise; when hot_cold, raise `WRONG_PHASE` with "Hot/cold mode has no pins.").

In `server/tests/api/test_modules_and_invite.py` `test_modules_schema_lists_classic_ids`, stop requiring `hot_cold` in the id set. Require `reveal_fuzzy` instead. Assert `location_mode` values are `["fuzzy", "precise", "hot_cold"]`.

- [ ] **Step 4: Run tests**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_reveal.py tests/engine/test_hot_cold.py tests/engine/test_power_ups.py -q && ruff check app/engine/modules/reveal_fuzzy.py app/engine/modules/hot_cold.py app/schemas/modules.py app/presets/classic.py`

Expected: PASS. `test_fuzzy_reveal_emits_pins_on_interval` still passes because the defaults are timed fuzzy.

- [ ] **Step 5: Commit**

```bash
git add server/app/schemas/modules.py server/app/presets/classic.py server/app/engine/modules/reveal_fuzzy.py server/app/engine/modules/hot_cold.py server/app/engine/state.py server/app/engine/views.py server/app/demo/controls.py server/tests/engine/test_reveal.py server/tests/api/test_modules_and_invite.py
git commit -m "feat: add precise and persistent reveals"
```

---

### Task 5: Rules editor locks and power-up prices

**Files:**
- Modify: `server/app/schemas/modules.py` (`locked` on tag, win, points, zone_policy; power-up rows)
- Modify: `server/app/presets/classic.py`
- Modify: `server/app/engine/modules/power_ups.py`
- Modify: `server/app/engine/views.py` (`power_ups` list)
- Modify: `server/tests/engine/test_power_ups.py`
- Modify: `ios/Manhunt/Domain/ModuleForm.swift`
- Modify: `ios/Manhunt/VisualModels.swift` (`VisualModule.locked`)
- Modify: `ios/Manhunt/PresetEditorView.swift`
- Modify: `ios/Manhunt/Domain/RulePreset.swift` (stop requiring reveal `enabled`)
- Modify: `ios/Manhunt/OfflineModuleSchema.json` (regenerate)
- Modify: `ios/Manhunt/LiveGameView.swift` (dock chips from the view)
- Modify: `ios/Manhunt/Networking/DTOs.swift`
- Modify: `ios/ManhuntTests/LiveHudAndPresetsTests.swift`

**Interfaces:**
- Consumes: `CATALOG` ids `ghost`, `decoy`, `radar`, `jammer`, `shield`, `scan`, `tracker`, `lockdown`. `grant_points` is not used here.
- Produces: schema `"locked": true` on `tag_policy`, `win`, `points`, `zone_policy`, `reveal_fuzzy`. Power settings `{id}_enabled` bool and `{id}_cost` int. View `power_ups`: `[{"id", "title", "cost", "role"}]` for tools the viewer can buy. `VisualModule.locked`.

- [ ] **Step 1: Write the failing tests**

Append to `server/tests/engine/test_power_ups.py`:

```python
def test_disabled_power_is_rejected_and_a_custom_cost_is_charged() -> None:
    session, clock, hider, seeker = two_player_hunt(
        {
            "power_ups": {
                "enabled": True,
                "ghost_enabled": False,
                "scan_enabled": True,
                "scan_cost": 10,
            }
        }
    )
    session.state.players[hider].points = 100
    with pytest.raises(GameRuleError):
        session.purchase(hider, "ghost")
    assert session.state.players[hider].points == 100
    session.state.players[seeker].points = 10
    session.purchase(seeker, "scan")
    assert session.state.players[seeker].points == 0
    assert session.state.players[seeker].points_earned == 0
```

Add a schema test in `server/tests/api/test_modules_and_invite.py` (or a new assertion in the existing modules test):

```python
def test_core_modules_are_locked_and_power_costs_are_fields(client) -> None:
    body = client.get("/v1/modules").json()
    modules = body["modules"]
    for module_id in ("tag_policy", "win", "points", "zone_policy", "reveal_fuzzy"):
        assert modules[module_id]["locked"] is True
        assert "enabled" not in modules[module_id]["fields"]
    assert modules["power_ups"]["locked"] is False
    assert modules["power_ups"]["fields"]["scan_cost"]["default"] == 25
    assert modules["power_ups"]["fields"]["ghost_cost"]["default"] == 20
    assert "hot_cold" not in modules
```

Use the test client's existing fixture name from that file (`client` or `api`). Match the fixture the file already uses.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_power_ups.py::test_disabled_power_is_rejected_and_a_custom_cost_is_charged tests/api/test_modules_and_invite.py -q`

Expected: FAIL. Ghost still purchases. Schema has no `locked` and no `scan_cost`.

- [ ] **Step 3: Implement**

`CATALOG` costs become: ghost 20, decoy 40, radar 40, jammer 55, shield 70, scan 25, tracker 50, lockdown 75.

`apply_purchase` resolves the spec through:

```python
def resolve_power(s: GameSession, power_id: str) -> dict[str, Any]:
    base = CATALOG.get(power_id)
    if base is None:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, f"Unknown power-up {power_id}.")
    settings = s.module_settings("power_ups")
    if not bool(settings.get("enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Power-ups are off.")
    if not bool(settings.get(f"{power_id}_enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "That power-up is off.")
    spec = dict(base)
    spec["cost"] = int(settings.get(f"{power_id}_cost", base["cost"]))
    return spec
```

Replace `spec = CATALOG.get(power_id)` in `apply_purchase` with `spec = resolve_power(s, power_id)`.

Schema `power_ups.field_order` is `enabled` plus, for each id in catalog order, `{id}_enabled` then `{id}_cost`. Titles are the dock names (Ghost, Decoy, Radar, Jammer, Shield, Scan, Tracker, Lockdown). Cost field: `_int(title + " cost", 0, 200, default, step=5, suffix="pts")`. Enabled field: `_bool(title, True)`. `power_ups` is not locked.

Add `"locked": True` to `tag_policy`, `win`, `points`, `zone_policy`, and `reveal_fuzzy`. Remove `enabled` from `reveal_fuzzy` if Task 4 left it out. Do not add `enabled` to tag, win, points, or zone_policy.

Classic `power_ups` lists `enabled: True` and each `{id}_enabled: True` plus the costs above.

`views.py` adds:

```python
"power_ups": _power_ups_for(session, viewer),
```

```python
def _power_ups_for(session: GameSession, viewer: PlayerState) -> list[dict]:
    from app.engine.modules.power_ups import CATALOG

    settings = session.module_settings("power_ups")
    if not bool(settings.get("enabled", True)):
        return []
    titles = {
        "ghost": "Ghost",
        "decoy": "Decoy",
        "radar": "Radar",
        "jammer": "Jammer",
        "shield": "Shield",
        "scan": "Scan",
        "tracker": "Tracker",
        "lockdown": "Lockdown",
    }
    rows = []
    for power_id, base in CATALOG.items():
        if base["role"] != viewer.role:
            continue
        if not bool(settings.get(f"{power_id}_enabled", True)):
            continue
        rows.append(
            {
                "id": power_id,
                "title": titles[power_id],
                "cost": int(settings.get(f"{power_id}_cost", base["cost"])),
                "role": base["role"],
            }
        )
    return rows
```

Regenerate the offline schema from the repo root:

```bash
cd server && . .venv/bin/activate && python -c '
import json
from app.schemas.modules import SCHEMAS
doc = {"modules": SCHEMAS, "order": list(SCHEMAS)}
with open("../ios/Manhunt/OfflineModuleSchema.json", "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
'
```

iOS `ModuleSchemaDTO` decodes `locked: Bool` default false. `VisualModule` gains `var locked: Bool`. `ModuleForm.module` sets `locked` from the schema. A locked module forces `enabled = true` and `tracksEnabled = false` even if an `enabled` field exists.

`PresetEditorView`: if `module.locked`, show the title and blurb as text and always show the rows. No `Toggle` for the card. Unlocked cards keep the current toggle, and rows show only when `module.enabled`.

Reveal row visibility lives in a pure helper so the test does not need SwiftUI:

```swift
enum RevealFormVisibility {
    static func shows(rowID: String, modules: [VisualModule]) -> Bool {
        guard let reveal = modules.first(where: { $0.id == "reveal_fuzzy" }) else { return true }
        func choice(_ id: String) -> String? {
            guard let row = reveal.rows.first(where: { $0.id == id }),
                  case let .options(_, values) = row.control,
                  values.indices.contains(row.choice) else { return nil }
            return values[row.choice]
        }
        func flag(_ id: String) -> Bool {
            reveal.rows.first(where: { $0.id == id })?.flag ?? true
        }
        let mode = choice("location_mode") ?? "fuzzy"
        let hintsActive = mode == "hot_cold" || (mode == "fuzzy" && flag("hints_enabled"))
        switch rowID {
        case "persistence", "interval":
            // Location timing only for Fuzzy and Precise. Hot/cold has no pins.
            return mode != "hot_cold"
        case "display":
            if mode == "hot_cold" {
                return choice("hints_persistence") != "persistent"
            }
            return choice("persistence") != "persistent"
        case "fuzz":
            return mode == "fuzzy"
        case "hints_enabled":
            // Extra toggle only under Fuzzy. Precise and Hot/cold hide it.
            return mode == "fuzzy"
        case "hints_persistence", "hints_interval":
            return hintsActive
        default:
            return true
        }
    }
}
```

`PresetEditorView` skips a row when `RevealFormVisibility.shows` is false. Only apply that filter to the `reveal_fuzzy` card.

`RulePreset.matching` stops reading `reveal_fuzzy` enabled. Match on round length, head start enabled and duration, and ping interval only. `apply` still sets the ping interval and does not call `setEnabled` for `reveal_fuzzy`.

`LiveHudAndPresetsTests.testRulePresetsMatchSchemaBoundsAndRoundTrip` keeps the ping interval assertion. It must not require `reveal_fuzzy.tracksEnabled`.

Dock: decode `powerUps: [PowerUpDTO]?` on `PlayerViewDTO` (`id`, `title`, `cost`, `role`). `LiveGameView` iterates that list for the viewer's chips. When the list is nil (older server), fall back to `SamplePark.powerUps`. When the list is empty, show no chips. `chipIsTappable` uses the server cost.

Update `SamplePark.powerUps` costs to the new defaults so the fallback matches.

- [ ] **Step 4: Run tests**

Run: `cd server && . .venv/bin/activate && pytest tests/engine/test_power_ups.py tests/api/test_modules_and_invite.py -q && ruff check app/schemas/modules.py app/engine/modules/power_ups.py app/engine/views.py app/presets/classic.py`

Expected: PASS.

Add an iOS test in `LiveHudAndPresetsTests`:

```swift
func testLockedModulesHaveNoMasterSwitchAndRevealHidesFuzzWhenPrecise() {
    let modules = ModuleForm.offlineModules()
    for id in ["tag_policy", "win", "points", "zone_policy", "reveal_fuzzy"] {
        let module = modules.first { $0.id == id }
        XCTAssertEqual(module?.locked, true, id)
        XCTAssertEqual(module?.tracksEnabled, false, id)
    }
    XCTAssertEqual(modules.first { $0.id == "power_ups" }?.locked, false)
    XCTAssertNotNil(modules.first { $0.id == "power_ups" }?.rows.first { $0.id == "scan_cost" })
    var edited = modules
    if let mIdx = edited.firstIndex(where: { $0.id == "reveal_fuzzy" }),
       let rIdx = edited[mIdx].rows.firstIndex(where: { $0.id == "location_mode" }),
       case let .options(_, values) = edited[mIdx].rows[rIdx].control,
       let precise = values.firstIndex(of: "precise") {
        edited[mIdx].rows[rIdx].choice = precise
    }
    XCTAssertFalse(RevealFormVisibility.shows(rowID: "fuzz", modules: edited))
    XCTAssertFalse(RevealFormVisibility.shows(rowID: "hints_enabled", modules: edited))
    XCTAssertTrue(RevealFormVisibility.shows(rowID: "interval", modules: edited))
    if let mIdx = edited.firstIndex(where: { $0.id == "reveal_fuzzy" }),
       let rIdx = edited[mIdx].rows.firstIndex(where: { $0.id == "location_mode" }),
       case let .options(_, values) = edited[mIdx].rows[rIdx].control,
       let hotCold = values.firstIndex(of: "hot_cold") {
        edited[mIdx].rows[rIdx].choice = hotCold
    }
    XCTAssertFalse(RevealFormVisibility.shows(rowID: "fuzz", modules: edited))
    XCTAssertFalse(RevealFormVisibility.shows(rowID: "persistence", modules: edited))
    XCTAssertFalse(RevealFormVisibility.shows(rowID: "hints_enabled", modules: edited))
    XCTAssertTrue(RevealFormVisibility.shows(rowID: "hints_interval", modules: edited))
}
```

- [ ] **Step 5: Commit**

```bash
git add server/app/schemas/modules.py server/app/presets/classic.py server/app/engine/modules/power_ups.py server/app/engine/views.py server/tests/engine/test_power_ups.py server/tests/api/test_modules_and_invite.py ios/Manhunt/Domain/ModuleForm.swift ios/Manhunt/VisualModels.swift ios/Manhunt/PresetEditorView.swift ios/Manhunt/Domain/RulePreset.swift ios/Manhunt/OfflineModuleSchema.json ios/Manhunt/LiveGameView.swift ios/Manhunt/Networking/DTOs.swift ios/ManhuntTests/LiveHudAndPresetsTests.swift
git commit -m "feat: lock core rules and price each power-up"
```

---

### Task 6: Distinct reveal colors and names

**Files:**
- Modify: `ios/Manhunt/Networking/DTOs.swift` (`RevealDTO.displayName`)
- Modify: `ios/Manhunt/Store/AppStore.swift` (stop stuffing reveals into `liveZones`)
- Modify: `ios/Manhunt/HuntMap.swift`
- Modify: `ios/Manhunt/LiveGameView.swift`
- Modify: `ios/Manhunt/Theme.swift` (palette only)
- Create: `ios/Manhunt/Domain/RevealPalette.swift`
- Test: `ios/ManhuntTests/LiveHudAndPresetsTests.swift`

**Interfaces:**
- Consumes: reveal `display_name`, `player_id`, `radius_m`, `lat`, `lon` from Task 4.
- Produces: `RevealPalette.index(for: UUID) -> Int` and `RevealPalette.color(at: Int) -> Color`. `HuntMap` parameter `reveals: [MapReveal]`.

- [ ] **Step 1: Write the failing test**

```swift
func testRevealPaletteIsStableAndNotAZoneColor() {
    let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!
    XCTAssertEqual(RevealPalette.index(for: id), RevealPalette.index(for: id))
    XCTAssertEqual(RevealPalette.index(for: id), 0xAB % 6)
    let first = RevealPalette.index(for: id)
    let second = RevealPalette.index(for: UUID())
    XCTAssertTrue((0..<6).contains(first))
    XCTAssertTrue((0..<6).contains(second))
}

@MainActor
func testLiveZonesDoNotIncludeReveals() {
    let store = AppStore.makePreview()
    let revealID = UUID()
    store.match = MatchHandle(
        snapshot: PlayerViewDTO(
            gameId: UUID(),
            joinCode: "TACO42",
            phase: .active,
            phaseRemainingS: nil,
            gameElapsedS: 10,
            timeLimitRemainingS: 1000,
            timers: nil,
            you: YouDTO(
                playerId: UUID(),
                role: .seeker,
                status: .active,
                isHost: true,
                bounds: BoundsDTO(phase: "inside", remainingS: nil),
                safeZone: nil,
                points: 0
            ),
            players: [],
            reveals: [
                RevealDTO(
                    revealId: revealID,
                    playerId: UUID(),
                    lat: 40.66,
                    lon: -73.96,
                    radiusM: 30,
                    expiresInS: 8,
                    displayName: "Riley"
                )
            ],
            banners: [],
            result: nil
        ),
        qrToken: nil
    )
    XCTAssertFalse(store.liveZones.contains { $0.id == revealID.uuidString })
    XCTAssertEqual(store.liveReveals.first?.name, "Riley")
    XCTAssertEqual(store.liveReveals.first?.radiusMeters, 30)
}
```

`store.match` is a `MatchHandle`. Give `RevealDTO.displayName` a default of nil so existing `RevealDTO` literals keep compiling.

- [ ] **Step 2: Run the test to verify it fails**

Run the iOS test class that holds these methods. Expected: FAIL because `RevealPalette` and `liveReveals` do not exist. If the simulator SDK is missing, say so and do not claim a pass.

- [ ] **Step 3: Implement**

`RevealPalette.swift`:

```swift
import SwiftUI

enum RevealPalette {
    /// First byte of the UUID. Stable across launches. Not sent by the server.
    static func index(for playerID: UUID) -> Int {
        let hex = playerID.uuidString.replacingOccurrences(of: "-", with: "")
        let byte = Int(hex.prefix(2), radix: 16) ?? 0
        return byte % 6
    }

    /// Violet, pink, cyan, lime, magenta, periwinkle.
    static func color(at index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.55, green: 0.36, blue: 0.96),
            Color(red: 0.96, green: 0.45, blue: 0.70),
            Color(red: 0.20, green: 0.85, blue: 0.85),
            Color(red: 0.78, green: 0.95, blue: 0.35),
            Color(red: 0.85, green: 0.25, blue: 0.55),
            Color(red: 0.75, green: 0.78, blue: 0.95),
        ]
        return colors[abs(index) % colors.count]
    }
}
```

`RevealDTO.displayName: String?` key `display_name`.

```swift
struct MapReveal: Identifiable, Hashable {
    var id: String
    var name: String
    var colorIndex: Int
    var center: VisualPoint
    var radiusMeters: Double
}
```

`AppStore.liveReveals` maps `snapshot.reveals` into `MapReveal`. `liveZones` returns `mapArena.zones` only, plus the spawn-lock zones the view already adds in `LiveGameView`. Remove the reveal append inside `liveZones`.

`HuntMap` takes `reveals: [MapReveal] = []`. For each reveal with `radiusMeters > 1`, draw a `MapCircle` with the palette color at opacity 0.22 and a dashed stroke, plus an `Annotation` of `name`. For `radiusMeters <= 1`, draw only the named annotation with a filled 16 pt circle in that color. Do not use `VisualZone.Kind.safe`.

In `zoneContent`, add an annotation of `zone.name` at the first point for `.safe`, `.outOfBounds`, and `.spawn` when the name is not empty. Do not label the play-area ring.

`LiveGameView` passes `reveals: store.liveReveals` and does not put reveals in `zones`.

- [ ] **Step 4: Run the test**

Run the same XCTest. Expected: PASS. Server pytest is unchanged in this task.

- [ ] **Step 5: Commit**

```bash
git add ios/Manhunt/Networking/DTOs.swift ios/Manhunt/Store/AppStore.swift ios/Manhunt/HuntMap.swift ios/Manhunt/LiveGameView.swift ios/Manhunt/Theme.swift ios/Manhunt/Domain/RevealPalette.swift ios/ManhuntTests/GameRulesTests.swift ios/ManhuntTests/LiveHudAndPresetsTests.swift
git commit -m "feat: name and color each fuzzy reveal"
```

---

### Task 7: Shorter status bar, one pause label, drop Acknowledge safety

**Files:**
- Modify: `ios/Manhunt/LiveHUD.swift`
- Modify: `ios/Manhunt/LiveGameView.swift`
- Modify: `ios/Manhunt/Store/AppStore.swift` (`recordLiveEvent`)
- Create: `ios/Manhunt/Domain/LiveHUDLayout.swift`
- Test: `ios/ManhuntTests/LiveHudAndPresetsTests.swift`

**Interfaces:**
- Consumes: `PhaseClock` strings. Event title `"paused"`.
- Produces: `LiveHUDLayout.clockPointSize == 20`, `showsSecondColumn == false`, `PauseChrome.shouldToast(eventTitle:)`.

- [ ] **Step 1: Write the failing test**

Append to `LiveHudAndPresetsTests`:

```swift
func testPauseIsOnlyTheClockLabel() {
    XCTAssertEqual(LiveHUDLayout.clockPointSize, 20)
    XCTAssertFalse(LiveHUDLayout.showsSecondColumn)
    XCTAssertFalse(PauseChrome.shouldToast(eventTitle: "paused"))
    XCTAssertTrue(PauseChrome.shouldToast(eventTitle: "resumed"))
    XCTAssertTrue(PauseChrome.shouldToast(eventTitle: "zone_warning"))

    let store = AppStore.makePreview()
    store.recordLiveEvent(
        BannerDTO(
            bannerId: UUID(),
            tone: "info",
            title: "paused",
            detail: "The host stopped the clock.",
            playerId: nil
        ),
        now: Date(timeIntervalSince1970: 2_000)
    )
    XCTAssertNil(store.liveUpdate)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL because `LiveHUDLayout` and `PauseChrome` do not exist, and the paused event becomes a live update.

- [ ] **Step 3: Implement**

`LiveHUDLayout.swift`:

```swift
enum LiveHUDLayout {
    static let clockPointSize: CGFloat = 20
    static let barHeight: CGFloat = 3
    static let showsSecondColumn = false
}

enum PauseChrome {
    static func shouldToast(eventTitle: String) -> Bool {
        eventTitle != "paused"
    }
}
```

`recordLiveEvent` returns immediately when `!PauseChrome.shouldToast(eventTitle: banner.title)`.

`LiveGameView` deletes the `if store.paused { banner(title: "Paused", ...) }` block. The host `confirmationDialog` deletes `Button("Acknowledge safety", action: store.acknowledgeSafety)`. Leave `acknowledgeSafety()` on the store.

Rewrite `LiveHUD.body` as one `HStack`:

- Leading `VStack` spacing 4: an `HStack` with `Text(clock.primaryLabel)` at caption2 and `Text(clock.primaryClock)` at `LiveHUDLayout.clockPointSize` bold rounded, then one `HuntProgressBar` of height `LiveHUDLayout.barHeight`.
- Trailing `VStack` alignment trailing, spacing 2: ping text `Ping \(clock.pingClock)` when `pingClock != nil`, and `clock.zoneLine` when present, both caption2, one line, `minimumScaleFactor` 0.75.
- No `Rectangle` divider. No second progress bar.
- Padding horizontal 12, vertical 6. Corner radius 14. Background and stroke stay.

`PhaseClock` is unchanged, including the paused caption test `testPhaseClockProgressHeadStartActiveAndDistances`.

- [ ] **Step 4: Run the test**

Run the `LiveHudAndPresetsTests` class. Expected: PASS, including the existing phase-clock assertions. If the simulator is unavailable, report that and do not claim an iOS pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Manhunt/LiveHUD.swift ios/Manhunt/LiveGameView.swift ios/Manhunt/Store/AppStore.swift ios/Manhunt/Domain/LiveHUDLayout.swift ios/ManhuntTests/LiveHudAndPresetsTests.swift
git commit -m "fix: show pause once and shorten the status bar"
```

---

## Self-review

Spec coverage:

- Seeker count, legacy hider inputs: Task 1.
- Start at 0, earned vs spendable, leaderboard and results: Task 2.
- Current awards unchanged, taunt toggle: Task 3. Award amounts stay out of the editor.
- Reveal header, fuzzy/precise, persistent/timed, hints: Task 4 and the visibility helper in Task 5.
- Locked tag, win, points, zones: Task 5.
- Power-up category toggle, per-tool toggle, per-tool cost, dock uses server costs: Task 5.
- Reveal colors and names, arena zone names: Task 6.
- One pause, shorter bar: Task 7.
- Acknowledge safety removed from the menu, route left in place: Task 7.

Placeholder scan: no TBD. The demo role block in Task 1 is the full replacement, including the `player_count >= 2` guard.

Type consistency: `assign_roles_random(seeker_count:)`, `assign_hiders_random(hider_count:)`, `grant_points(player, amount)`, `points_earned`, `you.taunt_enabled`, `you.points_earned`, `power_ups[].cost`, `RevealPalette.index(for:)`, `store.liveReveals`, `PauseChrome.shouldToast(eventTitle:)`.
