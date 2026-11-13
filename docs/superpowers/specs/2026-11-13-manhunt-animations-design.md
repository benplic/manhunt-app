# Manhunt live animations

Date: 2026-11-13. Status: implemented, device haptics pending — implementation follows `docs/superpowers/plans/2026-11-13-manhunt-animations.md`.

## Goal

Make the live clock, progress bar and player pins move smoothly in the PARK42 demo, flash the screen on a ping, preview and animate the zone shrink, and give custom buttons a press animation plus haptic.

## Architecture

The server adds one field (`timers.zone.interval_s`). Everything else is client-side. `ClockLead` extrapolates the 1 Hz snapshots, `PlayerGlide` interpolates pins, `ZoneShrinkPlan` turns the shrink countdown into a radius and a dashed preview, `PingDetector` spots the reveal countdown wrapping, and `HuntPressStyle` is the shared button feel. `HuntMap` and `LiveHUD` wrap their content in `TimelineView` (30 Hz) so only the live screen redraws per frame. The editor never opts in.

**Tech stack:** SwiftUI on iOS 18 (`TimelineView`, `KeyframeAnimator`, `sensoryFeedback`, MapKit), XCTest. FastAPI and pytest for the one server field.

## What I found (why the current build stutters)

- The server ticks once per second (`tick_loop` sleeps 1 s, then broadcasts). The phone gets one snapshot per second, so `PhaseClock` shows integer seconds that step. `HuntProgressBar` follows the same steps.
- Demo speed 2x/5x/10x runs N engine ticks per second. Timers and bot positions jump by N between snapshots.
- `HuntMap` draws each pin at the last snapshot coordinate, so pins teleport once per second.
- `HuntMap` never draws the shrinking zone from `timers.zone`. It draws the static `boundaryCircle`, which the server shrinks instantly in one step (`ZoneShrinkModule.on_tick`). There is no dashed next-zone ring today.
- The server only sends `radius_m`, `next_radius_m` and `shrinks_in_s`. The client cannot know "halfway between shrinks" without the interval, so the server must send it.
- The server `reveal` event is emitted only when pins were added, so hot/cold pulses and all-ghost pulses never fire it. Detecting the `next_reveal_in_s` wrap on the client is more reliable.
- Buttons are bare `Button` plus `.buttonStyle(.plain)` in 13 files. The only haptics today are the live-update pill and the out-of-bounds warning.

## Assumptions (no clarifying channel in this run; veto any at confirmation)

1. "Demo lobby" means the PARK42 sample game with bots, host speed 1x/2x/5x/10x and virtual walking. The fixes apply to every live game.
2. "Ping" is the reveal pulse (HUD "Ping 0:57"). Everyone in the match gets the flash. Hiders get red edges and a warning haptic ("you were exposed"). Seekers get yellow edges and a medium impact.
3. The dashed line is a dashed circle at `next_radius_m` that fades in once half of the shrink interval remains.
4. The shrink animation is the solid yellow ring contracting over the last quarter of the interval, landing on the dashed ring at the exact moment the server applies the shrink. I chose "before" over "after" the server shrink. A ring drawn larger than the real boundary after the shrink would show a player as safe while the server runs the out-of-bounds penalty. Early contraction only ever draws tighter than reality. If you meant "start animating after the shrink", only `ZoneShrinkPlan.visual` changes.
5. Haptics fire on press-down for custom-styled buttons. System-owned controls (alerts, confirmation dialogs, context menus, toolbar Done, Sign in with Apple, Toggle, Stepper, Picker) already animate and buzz, so they stay untouched. Haptics cannot be verified in the simulator.

## Approaches considered

- **Pins.** (A) Recompute `Map` content at 30 Hz inside `TimelineView`. Chosen: one code path for pins and the contracting ring. Risk is per-frame content diffing. (B) Float pins over the map with `MapReader.convert`: cheaper per frame, but the ring needs a meters-to-points conversion, z-order is wrong, and panning forces relayout. (C) Bridge `MKMapView`: best performance, large rewrite. Fallback is B if Instruments on a device shows heavy CPU (Task 3, Step 7).
- **Timer.** (Chosen) Extrapolate between snapshots with a one-tick cap. Rejected: send server ticks at 10 Hz. That is 10x websocket traffic and the wrong layer for a presentation problem.
