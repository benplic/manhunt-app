# Report examples

These are format samples. They are not findings in this repo. Copy the labels and the fields. Do not copy the facts.

## Critical/Mandatory

### Account with no deletion path

- Where: `ios/Profile/AccountService.swift:40`
- Seen: The app creates a server account and stores an auth token. No screen or request deletes the account or the token's server record.
- Rule: `https://developer.apple.com/app-store/review/guidelines/` — Account deletion — Apps that support account creation must let people initiate deletion inside the app.
- Why this label: The current guideline ties this to App Store rejection.
- Needs a person: Confirm the live guideline still says in-app initiation, and that support email is not an accepted substitute for this app.

## needs attention

### External link to buy the same digital item

- Where: `web/shop/Checkout.tsx:18`
- Seen: A button opens the publisher site to buy a digital unlock the app also sells.
- Rule: App Store guidelines, Payments — the current text requires in-app purchase for digital goods and describes narrow link exceptions.
- Why this label: Leaning towards being against the terms. The exception text does not clearly allow this button, and it does not clearly forbid this layout either.

## low risk

### Analytics event includes a free-text note

- Where: `server/app/telemetry.py:88`
- Seen: One event sends a player-typed note to the analytics vendor. Nothing else in the repo sends free text.
- Why this label: One field is less serious. If later events copy it, the app is sending user content to a vendor the privacy notice does not describe, which can become Critical/Mandatory.

## best practices

### Purpose string is a single vague word

- Where: `ios/Support/Info.plist:22`
- Seen: `NSCameraUsageDescription` is `Camera`. The system presents that string on the permission prompt.
- Tradition: Apple permission prompts — the usage string should say why this app uses the camera, in a full sentence.
- Seen: The key is present and only the wording is thin, so this is cosmetic.
