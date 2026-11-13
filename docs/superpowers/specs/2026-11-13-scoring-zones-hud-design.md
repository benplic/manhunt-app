# Scoring, zones, rules, and live HUD

Date: 2026-11-13. Status: implemented on `cursor/scoring-zones-hud-0d26`.

This spec covers the live seeker screen in the attached screenshot, the lobby role stepper, the rules editor, and the points economy. Implementation follows `docs/superpowers/plans/2026-11-13-scoring-zones-hud.md`.

## What earns points today

The spendable balance is `PlayerState.points`. It starts at **100**. Purchases subtract from it. The leaderboard and the results screen sort by that same balance, so a power-up purchase lowers your rank.

Nothing else pays. These five rules are the whole economy:

| Rule | Who | Amount | Trigger |
|---|---|---|---|
| Survival | Active hider | 10 | Every 300 seconds of active play. `last_survival_award_s` starts at 0, so the first award is at 5:00. |
| Close call | Hider | 20 | A seeker is within 15 m for at least 5 seconds, then the hider gets out to 30 m without being tagged. GPS only. A fix worse than the accuracy cutoff does not count. |
| Taunt | Hider | `max(5, 40 - nearest_seeker_m / 10)` | The hider broadcasts a precise location. A taunt on top of a seeker pays 40. A taunt 350 m or farther pays 5. Cooldown default 45 s, broadcast window 8 s. |
| Others tagged | Each hider still active | 15 | Another hider is tagged. |
| Tag | Seeker | 25 | A tag is accepted. Hardcoded in `TagPolicyModule`, not in the points settings. |

Joining, head start, standing in a zone, receiving a ping, hot/cold hints, and buying a power-up do not award points. The dock number in the screenshot (100) is the starting balance, not points earned in that hunt.

## Scoring decision

Three ways to make a 0 start playable:

1. **Keep the five awards. Lower the default power-up prices.** The awards already pay for different behavior: waiting (survival), escaping (close call), risking a precise ping (taunt), a teammate getting caught (others tagged), and catching someone (tag). New sources would pay the same moments twice, and GPS noise makes "distance traveled" a bad source.
2. **Keep today's prices (40–90) and raise the awards.** A seeker would need a fatter tag payout to buy Scan, and a quiet hider would need a faster survival drip. That inflates the leaderboard and makes taunt and close call less special.
3. **Add sources** (ping survived, time as seeker, zone visits). More rules to explain on the field, and seekers still have nothing to do but tag.

Use option 1.

"Lifetime points" means the running total **earned in this match**. It is not a career total across games. There is no profile store for that, and this spec does not add one.

Two counters, both starting at 0:

- `points` is the spendable balance. The dock shows it. Purchases subtract only here.
- `points_earned` increases by the same amount whenever `points` is granted, including the demo "add points" control. Purchases do not change it.

The in-game leaderboard and the end-of-game leaderboard sort by `points_earned`. Spending cannot drop a player down the board. A player who earned 80 and spent 75 still ranks as 80. Their dock reads 5.

Award amounts stay at the table above. Tag's 25 moves into the points grant helper so there is one function that updates both counters, and the amount stays 25.

Default prices, chosen so the first tool costs one solid action and later tools cost more catches or more risk. Hosts can change every price.

| Power-up | Role | Cost | Paid for by |
|---|---|---|---|
| Ghost | Hider | 20 | One close call |
| Decoy | Hider | 40 | One max taunt, or two close calls |
| Radar | Hider | 40 | Same |
| Jammer | Hider | 55 | A close call plus a taunt, or two tags' worth of survival time |
| Shield | Hider | 70 | Late, on purpose. Untaggable is the strongest hider tool. |
| Scan | Seeker | 25 | One tag |
| Tracker | Seeker | 50 | Two tags |
| Lockdown | Seeker | 75 | Three tags |

Taunt stays the high-variance hider action: closer to a seeker pays more, because the ping is more useful to that seeker. It can be turned off. When it is off, the hider dock hides the button and the server rejects `taunt`.

## Seeker count

The lobby stepper and the roles schema field `hider_count` set how many **hiders** are dealt. The customized number is the seeker count. Everyone else hides.

- Schema field `seeker_count`, title "Seekers", range 1–20, default **1**.
- Lobby stepper range is 1 through `players - 1`, so a game still has at least one hider.
- New randomize calls and new presets send `seeker_count`. The first N shuffled players are seekers.
- An old input or old preset that contains `hider_count` and no `seeker_count` still means that many hiders. Do not reinterpret a saved "2 hiders" as "2 seekers".
- Classic's role default becomes `seeker_count: 1`.

## Fuzzy zones on the map

Reveal circles are appended in `AppStore.liveZones` as `VisualZone` kind `.safe` with the name `"Reveal"`. Safe zones use the same blue (`HuntColor.safe`). The map draws no name. Several hiders, and a real safe zone, all look like one blue circle. The yellow ring is the play area. The orange shape is an out-of-bounds zone. That matches the screenshot.

Reveals are not safe zones.

- Draw them in their own layer.
- Fuzzy (`radius_m > 0`): dashed circle, fill at low opacity, name capsule at the center.
- Precise (`radius_m == 0`): a named pin, no circle.
- Name is the hider's display name. The reveal payload includes `display_name`.
- Color is chosen on the phone from the hider id: the first byte of the UUID (hex, dashes removed) modulo 6. The server does not send a color index. The six colors are not the play-area yellow, safe blue, out-of-bounds orange, seeker red, or hider green.
- Arena safe, out, and spawn zones keep their kind colors and gain a name capsule from `zone.name`. The play-area ring stays unlabeled.

## Reveal rules

Reveal is one rules section. It has no on/off switch. The hunt always has a reveal mode.

**Location mode** is a three-way segmented control, same control style as Tag method (QR / Ultra Wideband): **Fuzzy | Precise | Hot/cold**. No off position.

The section contains:

- **Location**, segmented: Fuzzy, Precise, or Hot/cold. Default Fuzzy.
- **Location timing**: Persistent or Timed. Shown for Fuzzy and Precise. Hidden for Hot/cold.
- Interval (20–600 s, default 60), display (5–60 s, default 10, shown only when timed), fuzz meters (0–100, default 30, shown only when Fuzzy).
- **Hints**, a toggle shown only when Location is Fuzzy. Default on. Hot/cold distance and direction run alongside the fuzzy pins when this is on. When Location is Hot/cold, hints are always on and this row is hidden. When Location is Precise, hints are off and this row is hidden.
- **Hints timing**: Persistent or Timed. Shown when hints are active (Fuzzy with Hints on, or Hot/cold mode). Update interval 2–30 s, default 5. Timed hints use the location display duration when a location pulse exists; in Hot/cold mode timed hints clear after `display` seconds from each refresh.

Behavior:

- **Fuzzy**, timed: today's reveal. A new circle on the interval, offset inside the fuzz radius, removed after `display` seconds. Optional hints when the Hints toggle is on.
- **Fuzzy**, persistent: the circle updates on the interval and does not expire. Optional hints.
- **Precise**, timed or persistent: the pin is the true position, `radius_m` is 0. No hot/cold hints. Persistent does not expire.
- **Hot/cold**: no location pins. Seekers only get distance and direction. Refresh every `hints_interval` (or timed clear after `display`).
- One current pin per hider when location pins run. A new pulse replaces that hider's previous pin.
- Hints persistent: today's hot/cold. Refresh every `hints_interval` while the hunt is active.
- Hints timed: publish on a pulse, then clear after `display` seconds. The dock returns to "No hint yet."
- Hints off (Fuzzy with toggle off, or Precise): clear the hint and do not publish another.
- `hot_cold` stays a loaded module so existing presets still tick. It reads the mode and hint fields from `reveal_fuzzy` when those keys are present. The editor does not show a separate Hot / cold card.
- The reveal module ignores an `enabled: false` left over from an old preset. Reveal mode cannot be switched off as a whole.

Schema field `location_mode` values: `fuzzy`, `precise`, `hot_cold`. Labels: Fuzzy, Precise, Hot/cold.

Module id stays `reveal_fuzzy` so saved games and `MODULE_TYPES` do not need a rename. The editor title is **Reveal**.

## Other rules sections

These cards have no master switch. Their rows stay editable:

- **Tag**: method, radius, result, pairing.
- **Win**: end condition, time limit.
- **Points**: taunt toggle (default on) and taunt cooldown. Award amounts are not editor rows.
- **Zones**: out-of-bounds countdown, hider penalty, safe visit, safe cooldown, edge margin.

These keep a master switch:

- Head start, zone shrink, going dark.
- **Power-ups**: the existing category switch, plus a switch and a cost stepper for each of the eight tools. Costs are integers from 0 to 200, step 5. A disabled tool is rejected by the server and omitted from the dock. The dock reads costs from the player view, not from the hardcoded `SamplePark.powerUps` list. Category off means an empty list.

The schema gains `"locked": true` on Tag, Win, Points, Zones, and Reveal. The preset editor renders a locked card as a header and its rows, with no toggle. `OfflineModuleSchema.json` is regenerated from `GET /v1/modules`.

## Live HUD

The screenshot shows Pause three times: the clock caption, a banner titled "Paused" whose detail is "The host stopped the clock.", and a black pill with that same sentence. The banner is client-only (`LiveGameView` when `store.paused`). The pill is the `paused` socket event recorded by `recordLiveEvent`.

The clock caption is the only pause indicator. Do not add the banner. Do not toast the `paused` event. A `resumed` toast can still show once.

The status card is a two-column block: a 28 pt clock, its own progress bar, a divider, a second progress bar, and the zone line. That height leaves an empty band over the map.

Replace it with one row:

- Caption and clock on one line. Clock is 20 pt, not 28. Caption stays "Paused", "Time left", "Head start", "Waiting", or "Ended".
- One 3 pt progress bar under the clock only.
- Trailing text: `Ping 0:57` when a reveal interval exists, otherwise omit it. Zone line stays one line, same copy `PhaseClock` already builds.
- No second column and no vertical divider.
- Card padding 6 vertical and 12 horizontal. Corner radius 14.

`PhaseClock` strings do not change. Only `LiveHUD` layout changes.

## Acknowledge safety

The host menu item calls `ack_safety`, which clears safety banners and sets `safety_needs_ack` false. It does not bring the phone back, cancel the going-dark penalty, or change who is lost. On the field it does nothing useful.

Remove **Acknowledge safety** from the host dialog. Leave the server route in place so an old client does not 404. Going-dark detection, the safety banner, and the signal-loss penalty stay.

## Out of scope

- Career totals across games.
- New point sources.
- Editing survival, close-call, or tag amounts in the rules UI.
- Removing signal-loss.
- Rebuilding Phase 0 or the Phase 1 engine beyond the fields this spec names.

## Testing

Server: `cd server && . .venv/bin/activate && pytest -q && ruff check .`

iOS, on a machine with the 18.4 simulator: `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`

Engine code must not call `datetime.now()` or the global `random`. Distances stay 111,320 m per degree. `is_decoy` stays off the wire. No coordinates or tokens in logs.

Known assertion to update: `test_qr_tag_eliminates_a_nearby_hider` expects seeker points `125` (the old 100 start plus 25). After the 0 start it expects `25`, and `points_earned` of 25.
