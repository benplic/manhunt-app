# Agent instructions

Read this before changing Manhunt. The roadmap is `docs/superpowers/plans/2026-11-09-manhunt-roadmap.md`. Unfinished work is `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md`. That gap file wins over any todo list, checklist, or earlier chat that says a phase is done.

## Do not mark work done early

A roadmap bullet is done only when its acceptance line in the remaining-benchmarks file is true in this repo.

- Stubs, drafts, and “the function exists” are not done. Say what is missing.
- Human gates stay open until a person does them. Do not check off a park playtest, a cellular tunnel check, an Azure deploy, or a TestFlight upload.
- Do not mark a parent phase complete while any of its bullets are open.
- After you finish an item, record the commit hash and the test name under Closed in the remaining-benchmarks file. Leave the acceptance line in place.
- If you did not run the test, say so. Do not report a pass you did not see.

## How to work

- One open benchmark at a time. Read that bullet in the roadmap and the acceptance line, then write the failing test, then implement.
- Do not rebuild Phase 0 or the Phase 1 engine. They are already in the tree.
- Do not edit the Cursor plan file under the agent store. The repo copies in `docs/superpowers/plans/` are the ones to update.
- New git branches use `cursor/<descriptive-name>-2a9d`, lowercase. Do not merge, open a PR, or deploy unless Scott asks.
- Code, comments, and docs are English. Unfinished behavior gets a `TODO:` comment. Do not swallow exceptions.
- No secrets in the repo. No coordinates or tokens in logs.

## Checks

- Server: `cd server && . .venv/bin/activate && pytest -q && ruff check .`
- iOS: `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`
- `ArenaEditorModel` is not `@MainActor`. The engine does not call `datetime.now()` or the global `random`. Distances use 111,320 m per degree, not haversine. `is_decoy` never goes out on the wire.
