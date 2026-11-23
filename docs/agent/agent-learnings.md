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
- Do not start a horizon mode unless Scott opens that goal.

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
