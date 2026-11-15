# Compliance signals

Look in the repo before asking. Cite the file that made a distributor clear. If none of these are decisive, ask. Do not score that store's rules yet.

## Distributor evidence

| Distributor | Clear evidence |
|---|---|
| Apple App Store | Xcode project or workspace, `Info.plist`, `PrivacyInfo.xcprivacy`, an App Store Connect export, or a shipping doc that names the App Store |
| Google Play | `android/` app module, `AndroidManifest.xml`, Play Billing, or a Play Console data-safety export |
| Steam | `steam_appid.txt`, a Steamworks integration, or a Steam depot / content-survey config |
| Website | A site that is the product (not only a marketing page for a native app): server routes, a deployed web client, cookie or analytics config, a privacy or terms page |
| Other store | Epic, Itch, console, or a sideload channel, only when a config or doc names it |

A native app can also have a website. Audit the website when the site collects accounts, payments, or analytics. Do not apply website privacy rules to a static README.

## Always look, whichever store

Search for these. A hit is a lead, not a finding, until you read the call site and the current rule.

- Accounts, auth tokens, session cookies, "sign in with" providers
- Payments, subscriptions, virtual currency, loot boxes, external purchase links
- Location, contacts, photos, microphone, camera, health, Bluetooth, tracking, advertising ID
- Analytics, crash, and ad SDK initialization; privacy nutrition or data-safety text that disagrees with those SDKs
- Age gates, kids or family copy, chat, user-generated content, reporting and blocking
- Background collection, silent push used to track, clipboard or contacts read without a purpose string
- Export-controlled encryption flags, private or undocumented APIs
- Scraped content, trademarked assets, fonts and SDKs whose license forbids the way they are shipped
- Secrets committed in the tree (report the path and the kind of secret, not the value)

Legal-shaped leads (privacy, children, payments, consumer claims) can be reported before a store is confirmed. Say which store rules you did not apply.

## What to open

Open the live page. Do not trust a section number from memory. Cite URL and heading.

- Apple: `https://developer.apple.com/app-store/review/guidelines/` and the privacy manifest docs linked from the current guidelines
- Google Play: Play Console policy center (`https://support.google.com/googleplay/android-developer`) — Developer Program Policies, Families, Payments, User Data
- Steam: Steamworks documentation on content rules, the content survey, and the Steam Distribution Agreement linked from the current partner docs
- Website: privacy and cookie rules for the regions the product actually serves. If the code does not name a region, ask before labeling a statute `Critical/Mandatory`

## Per-store checks

Apple: purpose strings match actual API use; privacy manifest and required-reason APIs; tracking permission before tracking; account deletion if accounts exist; Sign in with Apple when other third-party login is offered; digital goods paid with in-app purchase; Kids category rules if the product is for children.

Google Play: permissions match features; data-safety declarations match SDK behavior; Play Billing for digital goods; Families policy if the target audience includes children; account deletion if accounts exist.

Steam: depot contents match the content survey; no surprise kernel-level or overlay behavior the store forbids; user-generated content has a report path when the survey says the game has it; the build does not wrap a store the Distribution Agreement disallows.

Website: a privacy notice if the site collects personal data; consent before non-essential tracking where the applicable rule requires it; no card data stored in app logs or the repo; age-gating if the product is not for children but the content is restricted.

## Severity examples of kind, not of this repo

- Shipping a tracker before consent, or collecting children's data with no age gate, when the current rule forbids it: `Critical/Mandatory`
- A purchase link that might bypass the store billing rule but the guideline's exception is ambiguous: `needs attention`
- One screen collecting an email with no stated purpose, and the same pattern is easy to copy: `low risk`
- A Swift type name or an Android resource that breaks that platform's usual naming, with no policy consequence: `best practices`
