# Beta Compliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship every external-beta compliance fix that can land without an Apple Developer Program account, and remove ping sound / ping flashlight.

**Architecture:** Server enforces age and name rules and hard-deletes accounts. iOS adds an Account & Safety surface, Release baked API URL, Keychain home key, privacy/support Info.plist keys, purpose strings, privacy manifest, safety modal, report/block, and deletes ping-alert UI. Sign in with Apple stays hidden until the Apple plan.

**Tech Stack:** FastAPI + SQLAlchemy, SwiftUI iOS 18, XCTest / pytest, Info.plist / PrivacyInfo.xcprivacy.

**Spec:** `docs/superpowers/specs/2026-11-18-beta-compliance-design.md`

**Sibling plan (do not implement here):** `docs/superpowers/plans/2026-11-18-apple-developer-account.md`

## Global Constraints

- English copy only; unfinished behavior gets a `TODO:` comment.
- No secrets, tokens, or real coordinates in logs or commits.
- New ErrorCode values must be added to `server/app/errors.py` and `ios/Manhunt/Domain/ErrorCode.swift` together.
- Do not wire Sign in with Apple entitlement or show the SIWA button.
- Manual flashlight stays; only ping-triggered sound/torch go away.
- Release builds bake `MANHUNT_API_BASE_URL`; Debug keeps typed Server URL.
- TDD: failing test → implement → pass → commit per task.
- Branch naming if needed: `cursor/<descriptive-name>-2a9d`.

## File map

| Path | Responsibility |
|---|---|
| `docs/legal/privacy.md` | Privacy policy source |
| `server/app/errors.py` + `ios/.../ErrorCode.swift` | `TOO_YOUNG`, `NAME_BLOCKED` |
| `server/app/auth/names.py` | Display-name normalization + blocklist |
| `server/app/auth/routes.py` | Age on `/dev`, name check, `DELETE /v1/me` |
| `server/app/auth/delete.py` | Hard-delete + anonymize helper |
| `server/tests/api/test_auth_and_games.py` (extend) / `test_account_delete.py` | Auth age/name/delete tests |
| `ios/Support/Info.plist` | Purpose strings, privacy/support URLs, export flag |
| `ios/Support/Info-Debug.plist` | Same strings + debug ATS |
| `ios/Support/PrivacyInfo.xcprivacy` | UserDefaults CA92.1 |
| `ios/Manhunt.xcodeproj/project.pbxproj` | Release base URL, privacy file in resources |
| `ios/Manhunt/Auth/KeychainStore.swift` | Home-key account |
| `ios/Manhunt/Domain/DisplayNameRules.swift` | Client name filter (mirror server list) |
| `ios/Manhunt/Domain/PlayerBlockList.swift` | Local blocked player ids |
| `ios/Manhunt/Account/AccountView.swift` | Privacy, contact, delete |
| `ios/Manhunt/SignInView.swift` | Age, hide SIWA, Release hide server URL |
| `ios/Manhunt/Store/AppStore.swift` | Age, delete, block, safety flag, no ping alerts |
| `ios/Manhunt/LiveControls.swift` | Remove ping settings sheet |
| `ios/Manhunt/Location/AppSettings.swift` | Drop ping keys; keep Settings URL helper |
| `README.md` | Beta ops: URL, key, privacy publish |

---

### Task 1: Remove ping sound and ping flashlight

**Files:**
- Modify: `ios/Manhunt/Store/AppStore.swift`
- Modify: `ios/Manhunt/LiveControls.swift`
- Modify: `ios/Manhunt/LiveGameView.swift`
- Modify: `ios/Manhunt/Location/AppSettings.swift`
- Delete or gut: `ios/Manhunt/Location/PingSound.swift` (delete if unused)
- Modify/Delete: `ios/ManhuntTests/PingAlertSettingsTests.swift`
- Modify: `ios/ManhuntTests/LiveHudAndPresetsTests.swift` only if it asserts ping alerts

**Interfaces:**
- Consumes: `PingDetector.didPing` visual path only
- Produces: `apply(_:)` no longer calls sound/torch; `LiveControls` has no ping settings

- [ ] **Step 1: Write a failing test that ping no longer triggers sound or torch**

In `ios/ManhuntTests/PingAlertSettingsTests.swift`, replace ping-alert cases with one test:

```swift
func testPingDoesNotPlaySoundOrFlashTorch() {
    let defaults = UserDefaults(suiteName: "ping-gone-\(UUID().uuidString)")!
    let torch = RecordingTorch()
    let sound = RecordingPingSound()
    let store = AppStore(
        service: FakeGameService(),
        defaults: defaults,
        torch: torch,
        pingSound: sound
    )
    store.handlePingAlerts()
    XCTAssertEqual(sound.playCount, 0)
    XCTAssertEqual(torch.onCount, 0)
}
```

If `handlePingAlerts` is deleted, call the same path `apply` would have used: construct two views where `PingDetector.didPing` is true and assert sound/torch stay zero (mirror existing ping tests in this file).

- [ ] **Step 2: Run the test — expect FAIL** (still plays when flags were on, or method still flashes)

Run: `cd ios && xcodebuild test -project Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4' -only-testing:ManhuntTests/PingAlertSettingsTests`

- [ ] **Step 3: Remove ping alert feature**

1. Delete `handlePingAlerts()`, `setPingSoundEnabled`, `setPingFlashlightEnabled`, `pingSoundEnabled`, `pingFlashlightEnabled`, `pingTorchFlashSeconds`, `pingTorchTask`, and `pingSound` dependency from `AppStore` (keep `torch` for manual flashlight).
2. In `apply(_ view:)`, remove `handlePingAlerts()`; keep `pingPulse` / visual flash.
3. Simplify `LiveControls` to flashlight + speaker/mic only; delete `PingAlertSettingsSheet` and the gear button.
4. Update `LiveGameView` call site.
5. Strip ping keys from `AppSettings`; leave `url` / `open()`.
6. Delete `PingSound.swift` if nothing imports it; remove from the Xcode project.
7. Rewrite `PingAlertSettingsTests` for the new assertion; delete obsolete toggle tests.

- [ ] **Step 4: Re-run PingAlertSettingsTests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add ios/Manhunt ios/ManhuntTests
git commit -m "fix(ios): remove ping sound and ping flashlight alerts"
```

---

### Task 2: Error codes + display name rules (server)

**Files:**
- Modify: `server/app/errors.py`
- Create: `server/app/auth/names.py`
- Create: `server/tests/auth/test_names.py`
- Modify: `ios/Manhunt/Domain/ErrorCode.swift` (add matching cases now so clients stay aligned)

**Interfaces:**
- Produces: `ErrorCode.TOO_YOUNG`, `ErrorCode.NAME_BLOCKED`; `normalize_display_name(name: str) -> str`; `assert_display_name_allowed(name: str) -> None` raises `ApiError`

- [ ] **Step 1: Failing tests for name rules**

```python
# server/tests/auth/test_names.py
import pytest

from app.auth.names import assert_display_name_allowed, normalize_display_name
from app.errors import ApiError, ErrorCode


def test_normalize_strips_and_collapses_spaces():
    assert normalize_display_name("  Casey   Lee ") == "Casey Lee"


def test_blocked_token_rejected():
    with pytest.raises(ApiError) as exc:
        assert_display_name_allowed("hello badword")
    assert exc.value.code == ErrorCode.NAME_BLOCKED
```

Use one real blocked token from the list you put in `names.py` (pick a mild placeholder token like `badword` for the test fixture list, or the first entry of the production list).

- [ ] **Step 2: Run — expect FAIL** (module missing)

Run: `cd server && . .venv/bin/activate && pytest -q tests/auth/test_names.py`

- [ ] **Step 3: Implement**

`server/app/errors.py` — add:

```python
TOO_YOUNG = "TOO_YOUNG"
NAME_BLOCKED = "NAME_BLOCKED"
```

`server/app/auth/names.py`:

```python
"""Display name normalization and a small blocklist for beta."""

from __future__ import annotations

import re

from app.errors import ApiError, ErrorCode

# Keep short. Lowercase tokens matched as whole words after normalize.
_BLOCKED = frozenset(
    {
        # Maintainers: add tokens people should not broadcast on the map.
        "nigger",
        "faggot",
        "retard",
    }
)

_SPACE = re.compile(r"\s+")


def normalize_display_name(name: str) -> str:
    return _SPACE.sub(" ", name.strip())


def assert_display_name_allowed(name: str) -> None:
    cleaned = normalize_display_name(name)
    if not cleaned or len(cleaned) > 40:
        raise ApiError(ErrorCode.VALIDATION_FAILED, "Display name is invalid.", status_code=422)
    tokens = {t.lower() for t in re.split(r"[^a-zA-Z0-9]+", cleaned) if t}
    if tokens & _BLOCKED:
        raise ApiError(
            ErrorCode.NAME_BLOCKED,
            "That display name is not allowed.",
            status_code=422,
        )
```

Mirror codes on iOS:

```swift
case tooYoung = "TOO_YOUNG"
case nameBlocked = "NAME_BLOCKED"
```

- [ ] **Step 4: pytest PASS**

- [ ] **Step 5: Commit**

```bash
git add server/app/errors.py server/app/auth/names.py server/tests/auth/test_names.py ios/Manhunt/Domain/ErrorCode.swift
git commit -m "feat(auth): add name blocklist and TOO_YOUNG/NAME_BLOCKED codes"
```

---

### Task 3: Age gate on `POST /v1/auth/dev`

**Files:**
- Modify: `server/app/auth/routes.py`
- Modify: `server/tests/api/test_auth_and_games.py` (and any helper `_auth` sites that post without age)
- Modify: helpers under `server/tests/` that call `/v1/auth/dev`

**Interfaces:**
- Consumes: `assert_display_name_allowed`, `normalize_display_name`
- Produces: `DevAuthIn.age: int` required; age &lt; 13 → 403 `TOO_YOUNG`

- [ ] **Step 1: Failing tests**

```python
def test_dev_auth_rejects_under_13(client: TestClient) -> None:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": "Kid", "installation_id": str(uuid4()), "age": 12},
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "TOO_YOUNG"


def test_dev_auth_accepts_13(client: TestClient) -> None:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": "Teen", "installation_id": str(uuid4()), "age": 13},
    )
    assert response.status_code == 200
```

Update `_auth` helpers to send `"age": 18`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement in `DevAuthIn` + `dev_auth`**

```python
class DevAuthIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=40)
    installation_id: str = Field(min_length=8, max_length=80)
    age: int = Field(ge=0, le=120)

# inside dev_auth, after secret checks:
if body.age < 13:
    raise ApiError(
        ErrorCode.TOO_YOUNG,
        "Manhunt is not available for people under 13.",
        status_code=403,
    )
assert_display_name_allowed(body.display_name)
name = normalize_display_name(body.display_name)
```

- [ ] **Step 4: Full auth/game tests PASS** (`pytest -q tests/api/test_auth_and_games.py` and fix every `/v1/auth/dev` caller)

- [ ] **Step 5: Commit**

```bash
git add server/app/auth/routes.py server/tests
git commit -m "feat(auth): require age on dev sign-in and block under 13"
```

---

### Task 4: `DELETE /v1/me` hard delete

**Files:**
- Create: `server/app/auth/delete.py`
- Modify: `server/app/auth/routes.py` (`bind_me_routes`)
- Create: `server/tests/api/test_account_delete.py`

**Interfaces:**
- Produces: `async def delete_account(session, user: User) -> None`; route `DELETE /v1/me` → `{"ok": true}`

- [ ] **Step 1: Failing test**

```python
def test_delete_me_removes_user_and_tokens(client: TestClient) -> None:
    user = client.post(
        "/v1/auth/dev",
        json={"display_name": "Casey", "installation_id": str(uuid4()), "age": 20},
    ).json()
    headers = {"Authorization": f"Bearer {user['access_token']}"}
    client.put("/v1/me/device-token", json={"token": "devicetoken-12345678"}, headers=headers)
    gone = client.delete("/v1/me", headers=headers)
    assert gone.status_code == 200
    me = client.get("/v1/me", headers=headers)
    assert me.status_code == 401
    refresh = client.post("/v1/auth/refresh", json={"refresh_token": user["refresh_token"]})
    assert refresh.status_code == 401
```

Add a second test: create arena as host, delete account, confirm user row gone and arena deleted or orphaned per `delete.py` rules (owned arenas deleted).

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `delete_account`**

Behavior checklist:

1. Delete `RefreshToken` rows for `user.id`.
2. Delete `DeviceToken` for `user.id`.
3. Delete `RulePreset` and `ArenaRow` owned by user.
4. For `GamePlayerRow` rows: set related live session player `display_name` to `"Deleted player"` if session loaded; keep membership row but you must either NULL user_id (requires migration) **or** delete membership rows and leave games without that player. Prefer: delete `GamePlayerRow` for this user; if they are host of a lobby/live game, end or abandon that game via existing helpers if present — otherwise delete membership and leave a `TODO:` only if host transfer is missing (do not leave FK to deleted user).
5. Because `GamePlayerRow.user_id` FKs to `users.id`, **delete memberships first**, then delete `User`.
6. If FK prevents user delete, add a short Alembic migration only if required — prefer deleting dependent rows first so no migration is needed.

Wire:

```python
@me_router.delete("/me")
async def delete_me(session: AsyncSession = Depends(get_session), user=Depends(current_user)) -> dict:
    await delete_account(session, user)
    await session.commit()
    return {"ok": True}
```

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add server/app/auth/delete.py server/app/auth/routes.py server/tests/api/test_account_delete.py
git commit -m "feat(auth): hard-delete account via DELETE /v1/me"
```

---

### Task 5: Privacy policy doc + Info.plist keys + privacy manifest + export flag

**Files:**
- Create: `docs/legal/privacy.md`
- Modify: `ios/Support/Info.plist`
- Modify: `ios/Support/Info-Debug.plist`
- Create: `ios/Support/PrivacyInfo.xcprivacy`
- Modify: `ios/Manhunt.xcodeproj/project.pbxproj` (add privacy file to Resources; set Release `MANHUNT_API_BASE_URL` placeholder)

**Interfaces:**
- Produces: `ManhuntPrivacyPolicyURL`, `ManhuntSupportEmail` in Info.plist; UserDefaults reason declared

- [ ] **Step 1: Add `docs/legal/privacy.md`** with sections: Who we are; Data we collect (name, age, precise location, install id, home auth secret on device, optional push token); How location is shared with other players; Retention (7-day sensitive trail purge); Account deletion; No ads/tracking; Contact email placeholder `support@example.com` until replaced; Policy updates.

- [ ] **Step 2: Update both Info plists**

Purpose strings (Release + Debug), exact intent:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Manhunt uses your precise location during an open hunt to enforce the play area, safe zones, and tags, and to show your position to other players under the game rules (including safety alerts). Location stays active for that hunt, including when the phone is locked. Manhunt does not request Always access.</string>
<key>NSCameraUsageDescription</key>
<string>Manhunt uses the camera so a seeker can scan a hider's tag code, and may use the torch when you turn on the flashlight control.</string>
<key>ManhuntPrivacyPolicyURL</key>
<string>https://REPLACE_WITH_PUBLISHED_PRIVACY_URL</string>
<key>ManhuntSupportEmail</key>
<string>support@example.com</string>
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

`PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

Add the file to the Manhunt target Resources in `project.pbxproj`.

Set Release `MANHUNT_API_BASE_URL` in `project.pbxproj` to the cloud HTTPS origin (use `https://REPLACE_WITH_CLOUD_API_ORIGIN` until the human fills the real named-tunnel / Azure URL). Debug stays `http://localhost:8000`.

- [ ] **Step 3: Commit**

```bash
git add docs/legal/privacy.md ios/Support ios/Manhunt.xcodeproj/project.pbxproj
git commit -m "docs(legal): privacy policy draft and iOS privacy/export plist keys"
```

---

### Task 6: Keychain home key + iOS age + name filter + hide SIWA / Release server URL

**Files:**
- Modify: `ios/Manhunt/Auth/KeychainStore.swift`
- Create: `ios/Manhunt/Domain/DisplayNameRules.swift`
- Modify: `ios/Manhunt/SignInView.swift`
- Modify: `ios/Manhunt/Store/AppStore.swift`
- Modify: `ios/Manhunt/Networking/LiveGameService.swift` / `GameService.swift` / `FakeGameService.swift` / `APIClient` sign-in body
- Create: `ios/ManhuntTests/DisplayNameRulesTests.swift`
- Modify: `ios/ManhuntTests/AppStoreTests.swift`

**Interfaces:**
- Produces: `KeychainStore` home-secret account; `signIn(displayName:installationId:age:)`; `DisplayNameRules.isAllowed`

- [ ] **Step 1: Failing unit tests**

```swift
func testBlockedNameRejected() {
    XCTAssertFalse(DisplayNameRules.isAllowed("hello retard"))
}

func testAgeUnder13SetsTooYoungNote() async {
    // FakeGameService.signIn should throw ServiceError(code: .tooYoung, ...) when age < 13
}
```

- [ ] **Step 2: Implement client pieces**

1. Keychain: `homeSecretAccount = "home-secret"`; `saveHomeSecret` / `readHomeSecret` / clear on sign-out optional (keep secret across sign-out for party convenience — **keep** across sign-out, clear only on explicit user clear if you add one).
2. Stop writing `devAuthSecret` to UserDefaults; migrate once from defaults → keychain then remove defaults key.
3. `DisplayNameRules` mirrors server tokens.
4. `SignInView`: age `TextField`, privacy link (`Bundle` URL), `#if DEBUG` server URL field, **remove** `SignInWithAppleButton` until Apple plan.
5. Pass `age` in `/v1/auth/dev` JSON.
6. Map `TOO_YOUNG` / `NAME_BLOCKED` to user-visible notes.

- [ ] **Step 3: Tests PASS**

- [ ] **Step 4: Commit**

```bash
git add ios/Manhunt ios/ManhuntTests
git commit -m "feat(ios): age gate, name filter, keychain home key, hide SIWA"
```

---

### Task 7: Account screen — privacy, contact, delete

**Files:**
- Create: `ios/Manhunt/Account/AccountView.swift`
- Modify: `ios/Manhunt/HomeView.swift`
- Modify: `ios/Manhunt/Store/AppStore.swift`
- Modify: `ios/Manhunt/Networking/*.swift` — `deleteAccount()`
- Modify: `ios/ManhuntTests/AppStoreTests.swift`

**Interfaces:**
- Produces: `AppStore.deleteAccount()`; `GameService.deleteAccount()` → `DELETE /v1/me`

- [ ] **Step 1: Failing test** — FakeGameService records delete; store ends signed out with nil token.

- [ ] **Step 2: Implement AccountView** with links:

- Privacy (open `ManhuntPrivacyPolicyURL`)
- Email support (`ManhuntSupportEmail`)
- Delete account (confirmation dialog → API → `signOut()`)

Add Account entry on Home (toolbar or row).

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "feat(ios): account screen with privacy, support, and delete"
```

---

### Task 8: Report + block + safety modal

**Files:**
- Create: `ios/Manhunt/Domain/PlayerBlockList.swift`
- Modify: map/player list helpers in `AppStore` / `HuntMap` / lobby lists to skip blocked ids
- Modify: `LobbyView.swift` / live player UI — Report and Block actions
- Modify: `AppStore` — `hasAcknowledgedSafety` in UserDefaults; gate `enterLive()` once
- Tests: `PlayerBlockListTests`, safety acknowledgment test

**Interfaces:**
- Produces: `PlayerBlockList.isBlocked(_:)` / `block(_:)`; mailto report URL builder; `acknowledgeSafety()`

- [ ] **Step 1: Failing tests for block list hiding a player id**

- [ ] **Step 2: Implement**

Report mailto body must include `game_id`, `player_id`, display name. Block persists on device. Safety modal copy:

> Play only where it is legal and safe. You are responsible for your surroundings. Manhunt is not for reckless use on public roads or anywhere you could hurt yourself or others.

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "feat(ios): player report/block and first-hunt safety modal"
```

---

### Task 9: README + remaining-benchmarks note

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md` only if a human-gate line should mention privacy URL publish / cloud base URL (do not check off Apple gates)

- [ ] **Step 1: Document** Release baked API URL, home key, age ≥ 13, publish `docs/legal/privacy.md` to the URL in Info.plist, Account deletion, and pointer to Apple plan for TestFlight / SIWA.

- [ ] **Step 2: Commit**

```bash
git add README.md docs/superpowers/plans/2026-11-09-remaining-benchmarks.md
git commit -m "docs: external beta compliance ops and Apple plan pointer"
```

---

### Task 10: Full verification

- [ ] **Step 1: Server** — `cd server && . .venv/bin/activate && pytest -q && ruff check .`

- [ ] **Step 2: iOS** — `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`

- [ ] **Step 3: Manual checklist (human)**

1. Replace `ManhuntPrivacyPolicyURL` and publish `docs/legal/privacy.md`.
2. Replace `ManhuntSupportEmail`.
3. Set Release `MANHUNT_API_BASE_URL` to the real cloud origin.
4. Confirm Sign-in has age, no SIWA, no Server URL in Release.
5. Confirm ping gear / sound / torch-on-ping are gone; manual flashlight works.
6. Delete account on a throwaway user; confirm re-auth creates a new user.

- [ ] **Step 4: Commit any doc URL fixes** (no secrets)

---

## Spec coverage checklist

| Spec item | Task |
|---|---|
| Remove ping light/audio | 1 |
| Name filter (server+client) | 2, 6 |
| Age &lt; 13 blocked | 3, 6 |
| Account hard delete | 4, 7 |
| Privacy policy + in-app link | 5, 7 |
| Privacy manifest + export flag + purpose strings | 5 |
| Baked cloud URL / hide Server URL | 5, 6 |
| Home key Keychain | 6 |
| Hide SIWA | 6 |
| Contact mailto | 7 |
| Report + block | 8 |
| Safety / physical-harm copy | 8 |
| README / ops | 9–10 |
| Apple Program / SIWA / ASC / TestFlight | Sibling plan only |
