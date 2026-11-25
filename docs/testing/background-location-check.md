# Background location check (iOS, manual)

Part of `docs/superpowers/plans/2026-11-24-connection-health.md`, Task 5. This cannot be
automated: it needs a real phone with a locked screen.

The app uses When In Use plus the background location mode and `CLBackgroundActivitySession`.
It never requests Always authorization, and this test must not change that. Info.plist keeps
"Manhunt does not request Always access."

## What the code does now

- `LocationReporter.start()` opens `CLLocationUpdate.liveUpdates()` and a
  `CLBackgroundActivitySession`.
- `LocationReporter.restartIfStale()` runs when the app returns to the foreground during a
  live hunt (`AppStore.handleScenePhase`). If no update arrived for `LocationReporter.staleAfter`
  (30 s), it restarts the stream and the background session. `AppStore.lastLocationRestartAt`
  records when that happened.
- After every reconnect, `GameSocket` re-sends the newest fix right after `welcome`.

## Steps

1. Build the Debug app to a physical iPhone on the same server as the playtest (home server
   or Azure). Sign in. Grant **While Using the App** and precise location.
2. Create a hunt with at least two players (a second phone or the web client). Start it.
   Confirm your pin moves on the other player's map.
3. Note the time. Press the side button to lock the phone, then **carry it** (walk a loop
   outside, or ride along in a vehicle) for **10 minutes**. A phone left on a desk produces
   no movement, so you could not tell a dead location stream from a stationary one. If you
   also want the stationary case, repeat the run once with the phone on a desk and record it
   separately.
4. While locked, watch the other player's map and, on the server, the playtest log:
   `playtest-logs/games/<game_id>.jsonl`. Look for your player's `ws_disconnect` and
   `ws_reconnect` lines and their `platform` (`ios`), `close_code`, and `exc_type`.
5. Unlock after 10 minutes. Within a few seconds your pin should update and the meter beside
   the host controls should show four bars.

## What to record

| Question | Result |
| --- | --- |
| Run type (carried, or stationary on a desk) | TODO |
| Did your pin keep moving on the other map while locked (all 10 minutes)? | TODO: fill in after the run |
| If it stopped, at what minute? | TODO |
| Did the socket stay connected (no `ws_disconnect` for your player)? | TODO |
| After unlock, did the pin catch up without a restart? | TODO |
| Did `lastLocationRestartAt` get set (the foreground restart fired)? | TODO |
| iOS version and device | TODO |

## Decision rule

- Fixes and the socket kept arriving: done. Record the result in the plan.
- Fixes stopped while locked but resumed after unlock (foreground restart worked): the
  supported path is limited by the OS. Note the minute it stopped and bring that to the
  user.
- Fixes did not resume even after the restart, or the restart never fired: do **not** add
  Always. Bring the Always-authorization question back to the user with this data (minute
  stopped, device, iOS version, the log lines above).

## Result

TODO: not run yet. This needs a human with a phone. Update the table above and the plan when
done.
