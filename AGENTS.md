# Agent instructions

Read this before changing Manhunt. Then read these two files, every time, before planning, editing, or asking Scott a question:

1. `docs/agent/project-context.md` — what the product is. If Scott states a product fact in chat that is not already in the repo, append it there under Heard in conversation before the turn ends.
2. `docs/agent/agent-learnings.md` — restraints and lessons about testing and programming. Append a verified lesson there when the next agent would hit the same bug or the same wrong command.

Do not ask a question those files, this file, or the remaining-benchmarks file already answer.

The roadmap is `docs/superpowers/plans/2026-11-09-manhunt-roadmap.md`. Unfinished work is `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md`. That gap file wins over any todo list, checklist, or earlier chat that says a phase is done.

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

## Git identity (benplic only)

Only the **benplic** GitHub account may author or push commits in this repo.

- Allowed: GitHub user `benplic` (local `user.name` / `user.email` that map to that account; SSH host `github.com-benplic`).
- Forbidden author/committer or push identities: `splichta`, `cursoragent`, `bplichta01`, and any other non-`benplic` account.
- Before every `git commit` or `git push`, check `git config --get user.name`, `git config --get user.email`, and `git remote -v`. If the effective identity is forbidden or not `benplic`, stop and fix local repo config (do not rely on a global `bplichta01` identity). Do not pass `--author` to impersonate a forbidden account.
- Prefer this repo’s local git config over the machine global config when they disagree.

## Checks

- Server: `cd server && . .venv/bin/activate && pytest -q && ruff check .`
- iOS, on a machine that has the 18.4 simulator: `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`
- GitHub Actions uses that scheme and device, but selects an installed runtime. The macos-15 image's default Xcode is 16.4, whose simulator is iOS 18.5. Pinning 18.4 there makes `xcodebuild` exit 70 before tests start.
- `ArenaEditorModel` is not `@MainActor`. The engine does not call `datetime.now()` or the global `random`. Distances use 111,320 m per degree, not haversine. `is_decoy` never goes out on the wire.
