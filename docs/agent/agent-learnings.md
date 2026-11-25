# Agent learnings

Restraints and lessons about how to test and change Manhunt. Read `docs/agent/project-context.md` first for what the product is. Read this file for how to work on it.

Product decisions Scott states in chat go in the project context file, under Heard in conversation. A testing, tooling, or implementation lesson goes here.

## How to update this file

Append a lesson when all of these are true:

1. You verified it (a failing command, a test name, a line in the tree). An unverified hunch stays out.
2. The next agent would hit the same bug or the same wrong command.
3. It is not already a standing restraint below, or in `AGENTS.md`.

Format:

```
### YYYY-MM-DD — short title
What happened. What to do instead. The command or test that showed it.
```

Use America/New_York dates. Do not delete an older lesson. If a lesson becomes wrong, add a new one that says so and point at the old heading.

Do not store secrets, coordinates, tokens, or a person's private contact data here.

## Read order

Before any plan, edit, review, or question to Scott:

1. `AGENTS.md`
2. `docs/agent/project-context.md`
3. This file
4. The one open benchmark in `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md`, and the matching roadmap bullet, when the task is implementation

Ask Scott only what those sources do not answer. One question, not a list of questions the design spec already settled.

## Standing restraints

### Scope

- One open benchmark at a time. Read its acceptance line. Write the failing test. Then implement.
- A bullet is done only when that acceptance line is true in this repo. A stub is not done. Say what is missing.
- Human gates stay open until a person does them: park playtest, cellular tunnel check, Azure deploy, TestFlight upload, a phone receiving a push.
- Do not mark a parent phase complete while any of its bullets are open.
- After finishing an item, record the commit hash and the test name under Closed in the remaining-benchmarks file. Leave the acceptance line in place.
- If you did not run the test, say so. Do not report a pass you did not see.
- Do not rebuild Phase 0 or the Phase 1 engine.
- Do not edit the Cursor plan file under the agent store. Update the copies in `docs/superpowers/plans/`.
- Do not start a feature, a horizon mode, or an iOS/web parity project unless Scott names that task. On 2026-11-23 he said to leave features alone. Human gates stay his.

### Code

- English in code, comments, and docs.
- Comment non-obvious rules, trade-offs, and intent. Do not comment the obvious.
- Unfinished behavior gets a `TODO:` comment that says what is left.
- Catch specific exception types. If the handling is unclear, leave the handler and a `TODO:`. Do not swallow an exception.
- No secrets in the repo. No coordinates or tokens in logs.
- Server style: ruff line length 100, lint select `E`, `F`, `I`, `UP`, target Python 3.12. `requires-python` is `>=3.12`. The Docker image is `python:3.13-slim`. If a wheel fails on a local 3.14 interpreter, run `docker compose --profile test run --rm server-test`.

### Engine and clients (bugs these prevent)

- Engine time: `Clock`. Engine randomness: `random.Random(seed)`. No `datetime.now()` and no global `random` under `server/app/engine/`.
- Distances: 111,320 m per degree. Not haversine.
- Outbound state: `build_view` only. `is_decoy` stays off the wire.
- `ArenaEditorModel` is not `@MainActor`. `AppStore` is.
- iOS files are picked up from the synchronized folders. Do not add file references to `project.pbxproj`.
- New `ErrorCode` values land in `server/app/errors.py` and `ios/Manhunt/Domain/ErrorCode.swift` together.
- Display-name blocklist tokens stay identical in `server/app/auth/names.py` and `ios/Manhunt/Domain/DisplayNameRules.swift`.
- Join-code alphabet stays identical in the server, Swift, and `web/src/api/joinCode.ts`.

### Git

- Only the **benplic** GitHub account may author or push. Remote host alias: `github.com-benplic`.
- Forbidden author, committer, or push identities: `splichta`, `cursoragent`, `bplichta01`, and any other non-`benplic` account.
- Before every commit or push, check `git config --get user.name`, `git config --get user.email`, and `git remote -v`. This repo's local identity is the one that matches existing commits. The machine global identity is a forbidden account. If the effective identity is not the local benplic identity, stop. Do not pass `--author` to impersonate anyone.
- Standing branch name in `AGENTS.md`: `cursor/<descriptive-name>-2a9d`, lowercase. A cloud-agent run may require a different suffix for that run. Use the suffix that run requires. Do not rewrite the standing `-2a9d` rule unless Scott changes it.
- Do not merge or deploy unless Scott asks. Do not open a pull request from an IDE session unless he asks. A cloud-agent run whose own instructions require a pull request may open one for that run only.

### Security

- Dev auth cannot be on when `MANHUNT_ENV` is `azure` or `prod`.
- `home`, `azure`, and `prod` must not boot on a known default signing key, trail key, or database password.
- Location trails are encrypted. Reads are audited. Retention default is 7 days.
- The web client stores the home key in `localStorage`. Do not copy that storage choice into iOS. iOS uses the Keychain.
- Do not suggest skipping a deploy approval, a reviewer environment, or any other control.

## Checks

Server, from `server/` with the venv active:

```bash
pytest -q && ruff check .
```

Web, from `web/`:

```bash
npm test && npm run build
```

iOS, on a machine that has the 18.4 simulator:

```bash
xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'
```

GitHub Actions uses that scheme and device, and selects an installed runtime. The macos-15 image's default Xcode is 16.4, whose simulator is iOS 18.5. Pinning 18.4 there makes `xcodebuild` exit 70 before tests start. A cancelled iOS job with no steps is usually a runner queue, not a test failure.

Run the suite for the side you changed. Say which commands you did not run.

## Why these two files

Scott asked on 2026-11-23 for a split that survives across agents.

- Project facts, including something he says in chat that is not in the repo, go in `docs/agent/project-context.md`.
- Testing and programming lessons go in this file.
- Both are read first, every time. The short pointer is the top of `AGENTS.md` and `.cursor/rules/read-agent-context.mdc`.

Rejected alternatives: pasting the whole architecture into `AGENTS.md` (that file is the short law; a long paste hides the restraints), and putting the full context only in a Cursor rule (other agents read `AGENTS.md`, and a rule that restates the architecture goes stale in two places).

## Lessons

### 2026-11-23 — Do not re-interview the repo

Scott asked for a brainstorm and also said not to ask questions the repo already answers. The design spec, roadmap, remaining-benchmarks file, and `docs/agent/project-context.md` already settle the game, the clients, the visibility rules, and the open human gates. Ask only a gap those sources leave open. One question.

### 2026-11-23 — Next product goal is hold

He answered the one open product question: leave features alone, take only bugs or tasks he names, and leave the human gates to him. The decision is in `docs/agent/project-context.md` under Heard in conversation. Do not ask it again.

### 2026-11-23 — Preserve WebSocket callback order across the main-actor hop

Separate `Task { @MainActor }` blocks do not guarantee that sequential socket
callbacks reach `AppStore` in receive order. Route all live-service callbacks
through one main-queue FIFO instead. The regression is
`testLiveCallbacksKeepFinalTagBeforeImmediatelyFollowingEndedView`.

### 2026-11-25 — iOS suite: a mid-run "TEST FAILED" with 0 failures is a crash
`xcodebuild test` printed `Executed N tests, with 0 failures` and still ended `** TEST FAILED **`, with `Restarting after unexpected exit, crash, or test timeout` in the log. The host process had segfaulted in `APIClient.once` (`URL(string:relativeTo:)`, `0xdeadbeef`) while `AppStoreTests.testSignInWithAppleHitsTheFake` ran. Thread Sanitizer (`-enableThreadSanitizer YES`) showed the cause: `FakeGameService` was a plain class whose dictionaries and counters were mutated from fire-and-forget `Task`s on several pool threads, so the heap was corrupted and a later, unrelated read crashed. `FakeGameService` is now `@MainActor`; a test that calls it directly must be `@MainActor` too. To find the crash, run `python3` over the newest `~/Library/Logs/DiagnosticReports/Manhunt-*.ips`, or diff `started` against `passed` test names in the log. Do not just rerun until green.

### 2026-11-25 — An empty plan checklist does not mean the work is unbuilt
`docs/superpowers/plans/2026-11-24-alert-noise.md` had every box empty, yet `AlertPresenter.swift`, `alertQueue.ts`, `useAlert.ts`, `test_final_ping.py`, and the warmth-line removal were already in `0450362`. "Build the plan" meant audit first: `git log --oneline -- <file>` for each file the plan names, `rg` for the string it removes, then run the suites. Only the gap (a `sendFinalPing` regression test) needed code. Do not rewrite finished work from a stale checklist.

### 2026-11-25 — jsdom cannot show that a banner does not resize the map
Vitest has no layout engine, so `LiveMapCss.test.ts` can only pin the CSS text (`position: absolute`, a zero-height `.alert-anchor`). To measure it, serve a small HTML page that inlines the real `web/src/screens/LiveMap.css` around the same chrome as `LiveMap.tsx`, then read `getBoundingClientRect()` on `.map-frame` with and without a banner at 375x667 and 667x375 (CDP `Emulation.setDeviceMetricsOverride`, cleared afterward). That is a harness, not the live app. Say so when you report it.

### 2026-11-25 — A view `body` with `return` silently drops later siblings
`LiveGameView.body` began with `let` statements and `return ZStack { ... }`, and `PingFlashOverlay(...)` was written after it. Once `return` is present the result builder is off, so the overlay never mounted, and the ping flash and haptic never ran, since `c19e3dd`. The only signal was a compiler warning, `code after 'return' will never be executed`, which is easy to miss in a test log. Attach extra layers with `.overlay { }` on the returned view. After touching a SwiftUI body, `touch` the file, run `xcodebuild build`, and `rg "LiveGameView.swift:[0-9]+:[0-9]+: warning"` the log.

### 2026-11-25 — `test_thirty_player_stress` fails only inside the Cursor sandbox
`tests/load/test_thirty_player_stress.py::test_full_lobby_ws_stress_passes` failed with `PermissionError: Operation not permitted: 'ps'` (`join_not_clean`, `sockets_open=0<40`). The harness shells out to `ps`, which the agent sandbox blocks. It passed when the same suite ran unsandboxed, so it is not a code or timing flake. It only looked random because a `pytest`-only command ran unsandboxed while a command chained after `npm` ran sandboxed. Run the server suite on its own, or request `all` permissions, before treating that failure as a regression.
