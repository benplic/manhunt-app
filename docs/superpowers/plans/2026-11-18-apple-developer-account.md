# Apple Developer Account Work — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish everything from the beta compliance audit that requires an Apple Developer Program membership, App Store Connect, or a working Sign in with Apple capability.

**Architecture:** Human enrolls in the Program, then aligns bundle id / Apple audience / entitlements, fills App Store Connect metadata, enables Sign in with Apple end-to-end, and uploads the first external TestFlight build with Beta App Review notes. Repo compliance work in `2026-11-18-beta-compliance.md` must already be done (or land in parallel except SIWA UI).

**Tech Stack:** Apple Developer Program, App Store Connect, Xcode capabilities, existing FastAPI Apple JWKS verifier (`server/app/auth/apple.py`), Swift `AuthenticationServices`.

**Spec:** `docs/superpowers/specs/2026-11-18-beta-compliance-design.md` §4 Out of scope (Apple plan)

**Sibling plan:** `docs/superpowers/plans/2026-11-18-beta-compliance.md` (repo work without Program access)

## Global Constraints

- Do not commit `.p8`, `.p12`, provisioning profiles, or App Store Connect API keys.
- Keep `DEVELOPMENT_TEAM` and bundle id changes intentional; document the final bundle id in README.
- Server `MANHUNT_APPLE_AUDIENCE` must equal the iOS bundle id that Sign in with Apple uses.
- External TestFlight still must comply with App Review Guidelines (2.2).
- English only; no secrets in logs.

## File map (when code changes)

| Path | Responsibility |
|---|---|
| `ios/Manhunt/Manhunt.entitlements` | Sign in with Apple capability |
| `ios/Manhunt.xcodeproj/project.pbxproj` | Bundle id / team / Release URL if not already set |
| `ios/Manhunt/SignInView.swift` | Show SIWA button again |
| `server/app/config.py` / `.env` / Azure secrets | `MANHUNT_APPLE_AUDIENCE` |
| `README.md` | Final bundle id, SIWA setup notes |
| App Store Connect (not in git) | Privacy URL, Support URL, nutrition labels, age rating, TestFlight |

---

### Task 1: Enroll and create the App Store Connect app

**Files:** none in git (human gate)

- [ ] **Step 1: Enroll** in the Apple Developer Program ($99/year) with the account that will own Manhunt.

- [ ] **Step 2: Create the app** in App Store Connect with the bundle id you will ship (today’s Xcode id is `com.benjaminplichta.manhunt`; TestFlight export options historically mentioned `app.manhunt.ios` — **pick one** and use it everywhere).

- [ ] **Step 3: Record the chosen bundle id** in a short README note under Azure / TestFlight (no secrets).

- [ ] **Step 4: Commit README note only**

```bash
git add README.md
git commit -m "docs: record App Store Connect bundle id for Manhunt"
```

---

### Task 2: Align bundle id, Apple audience, and entitlements

**Files:**
- Modify: `ios/Manhunt/Manhunt.entitlements`
- Modify: `ios/Manhunt.xcodeproj/project.pbxproj` (if bundle id changes)
- Modify: `server/app/config.py` default and `server/.env.example` `MANHUNT_APPLE_AUDIENCE`
- Modify: `.github/workflows/testflight.yml` provisioning bundle key if it still says `app.manhunt.ios`

**Interfaces:**
- Produces: entitlements contain Sign in with Apple; audience string == bundle id

- [ ] **Step 1: In Apple Developer → Identifiers**, enable **Sign in with Apple** on the App ID for the chosen bundle id.

- [ ] **Step 2: Set entitlements**

`ios/Manhunt/Manhunt.entitlements` should contain:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Set `MANHUNT_APPLE_AUDIENCE`** (server env + example) to the **exact** bundle id string.

- [ ] **Step 4: Add a server test** that documents audience mismatch failure mode (token with wrong `aud` → 401) if one does not already exist in `server/tests` for Apple auth.

- [ ] **Step 5: Commit repo-side alignment**

```bash
git add ios/Manhunt/Manhunt.entitlements ios/Manhunt.xcodeproj/project.pbxproj server/app/config.py server/.env.example .github/workflows/testflight.yml
git commit -m "feat(ios): enable Sign in with Apple entitlement and align audience"
```

---

### Task 3: Restore Sign in with Apple UI and verify end-to-end

**Files:**
- Modify: `ios/Manhunt/SignInView.swift` (re-add button removed/hidden in compliance plan)
- Modify: `ios/Manhunt/Store/AppStore.swift` only if error copy needs ASC-specific hints
- Test: `ios/ManhuntTests/AppStoreTests.swift` (fake SIWA path still works)

- [ ] **Step 1: Re-introduce `SignInWithAppleButton`** on Sign-in below Play, with the existing footnote that SIWA is for cloud games. Keep age field required before either path if the compliance plan already collects age (for Apple path: send age only if server gains an age field on `/v1/auth/apple` — **if Apple route has no age yet**, add `age` to `AppleAuthIn` the same way as dev auth and reject `&lt;13`).

- [ ] **Step 2: Failing test for Apple auth age &lt; 13** (server) if you add age to `/v1/auth/apple`:

```python
def test_apple_auth_rejects_under_13(client, monkeypatch):
    # stub verify_apple_token → "apple-sub-1"
    response = client.post(
        "/v1/auth/apple",
        json={"identity_token": "stub", "display_name": "Kid", "age": 12},
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "TOO_YOUNG"
```

- [ ] **Step 3: On a physical device** signed into an Apple ID, tap SIWA against the cloud API; confirm user row gets `apple_sub` and tokens return.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(ios): restore Sign in with Apple for cloud beta"
```

---

### Task 4: App Store Connect privacy, support, nutrition labels, age rating

**Files:** none required in git (human in ASC). Optionally ensure `ManhuntPrivacyPolicyURL` / `ManhuntSupportEmail` in Info.plist already match the public URLs from the compliance plan.

- [ ] **Step 1: Privacy Policy URL** in App Store Connect → App Privacy / product page fields → same HTTPS URL as in-app (`docs/legal/privacy.md` published).

- [ ] **Step 2: Support URL** — a public page or `mailto:`-reachable site listed in ASC; must match Guideline 1.5 expectations.

- [ ] **Step 3: App Privacy nutrition labels** — declare at least: Name, Precise Location (linked to gameplay, shared with other players on-device/server as applicable), User ID / Device ID as used; **no** tracking; no ads. Keep aligned with the privacy policy.

- [ ] **Step 4: Age rating questionnaire** — answer honestly for a real-world chase / location-sharing game among friends (not Kids Category; do not use “For Kids” in metadata).

- [ ] **Step 5: Export compliance** — if ASC still asks despite `ITSAppUsesNonExemptEncryption=false`, answer that only exempt encryption is used (HTTPS).

---

### Task 5: TestFlight external beta + Beta App Review notes

**Files:**
- `.github/workflows/testflight.yml` (secrets stay in GitHub Environment `prod`)
- Human: App Store Connect TestFlight groups

- [ ] **Step 1: Put signing secrets** in GitHub Environment `prod` as listed in the workflow (`BUILD_CERTIFICATE_BASE64`, profile, ASC API key, etc.). Never commit them.

- [ ] **Step 2: Ensure Release `MANHUNT_API_BASE_URL`** is the live cloud origin before archive.

- [ ] **Step 3: Run** `workflow_dispatch` on TestFlight workflow; confirm upload succeeds.

- [ ] **Step 4: Create external tester group**; first build triggers Beta App Review.

- [ ] **Step 5: Notes for Review** must include:

1. Cloud base URL is baked in (no typed server field in Release).
2. Home key / party secret for Play (rotate after review if needed).
3. How to create/join a sample or small hunt.
4. That precise location is required for a live hunt; use simulator GPX or a park.
5. Account deletion path: Home → Account → Delete account.
6. Privacy policy URL.
7. Age must be 13+.

- [ ] **Step 6: Confirm** external testers can install, sign in, and finish one hunt.

---

### Task 6: Push (optional for this beta)

Only if you want invite/start pushes working on TestFlight:

- [ ] **Step 1: Enable Push Notifications** capability on the App ID; add `aps-environment` to entitlements.

- [ ] **Step 2: Create APNs key**; store `MANHUNT_APNS_KEY` / key id / team id in server secrets (not git).

- [ ] **Step 3: Verify** `PUT /v1/me/device-token` after auth on device.

If push is deferred, leave a `TODO:` in README and skip this task.

---

### Task 7: Verification checklist

- [ ] SIWA works on device against cloud API with matching audience.
- [ ] Under-13 rejected on Apple auth if age was added.
- [ ] ASC privacy URL + support URL open in Safari.
- [ ] Nutrition labels match actual collection (location, name, identifiers).
- [ ] External TestFlight build approved; testers not paid (Guideline 2.2).
- [ ] Account deletion still works for Apple-created users (extend `delete_account` if `apple_sub` users missed any row type).
- [ ] Commit any final README updates (no secrets).

```bash
git add README.md
git commit -m "docs: TestFlight and Sign in with Apple setup complete"
```

---

## Spec coverage checklist

| Apple-only item | Task |
|---|---|
| Program enrollment + ASC app | 1 |
| SIWA entitlement + audience/bundle alignment | 2 |
| SIWA UI + E2E | 3 |
| ASC privacy URL, support, nutrition, age rating, export Q | 4 |
| TestFlight upload + Beta App Review notes | 5 |
| Push entitlement / APNs | 6 (optional) |
| Final verification | 7 |
| In-app privacy/deletion/age/report/block/ping removal/etc. | Sibling compliance plan |
