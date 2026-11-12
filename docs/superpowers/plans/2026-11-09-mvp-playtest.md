# MVP playtest gate

Human-run. The agent cannot play a three-phone park game.

## Simulator GPX

1. Start `docker compose up` so `http://localhost:8000/v1/healthz` is 200.
2. Run two iOS Simulator destinations (or one sim + one phone).
3. Xcode → Debug → Simulate Location → `ios/Support/GPX/riverside.gpx`.
4. Sign in with different display names, create a game on Riverside Green, join with the code.
5. Randomize roles, start, wait out head start, confirm a reveal circle, walk the GPX out of the play area on a hider, confirm the OOB banner, then scan a QR token from the DEBUG paste field if the camera is unavailable.

## Park game (three sideloaded phones)

Against the home server, over cellular, confirm:

- [ ] Join with a 6-character code
- [ ] Head start map lock for seekers
- [ ] A fuzzy reveal for seekers
- [ ] A hider out-of-bounds elimination
- [ ] A seeker out-of-bounds pin visible to hiders
- [ ] A QR tag
- [ ] A going-dark alert when a phone is silenced
- [ ] Flashlight button toggles the device torch on hardware and turns off when leaving or backgrounding
- [ ] Circle play-area zone shrink updates the boundary on-device and pushes out-of-bounds alerts

Paste the tunnel URL into the app's Server URL field. Keep `caffeinate -dims` running on the Mac.
