# LedgerLite

iOS expense and subscription tracker. Swift 5.9+, SwiftUI, SwiftData, iOS 17+.

## Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Getting started

```bash
git clone <repo-url>
cd LedgerLite
xcodegen generate
open LedgerLite.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and is not committed to version control.
Run `xcodegen generate` any time `project.yml` changes.

## Run on your iPhone (free Apple ID / Personal Team)

1. Xcode → **Settings → Accounts** → sign in with your Apple ID.
2. **LedgerLite** target → **Signing & Capabilities** → **Automatically manage signing** → Team: **(Personal Team)**.
3. Repeat for **LedgerLiteWidget** (same team).
4. Select your iPhone → **⌘R**.

**iCloud is not included in entitlements** until Phase 7.5 — Apple’s free Personal Team does not support the iCloud capability on device. Local SwiftData works fine without it.

If signing still fails on **App Groups**, register `group.com.enes.ledgerlite` in the [Developer Portal](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) (free account can create App Group IDs), then click **Try Again** in Xcode.

## CloudKit & App Group setup (Phase 7.5 / paid program)

> **TODO: CLOUDKIT** — the following must be done in the Apple Developer Portal before
> iCloud sync works (requires **paid** Apple Developer Program):
>
> 1. Register the **App Group**: `group.com.enes.ledgerlite`
>    → https://developer.apple.com/account/resources/identifiers/list/applicationGroup
>
> 2. Register the **CloudKit container**: `iCloud.com.enes.ledgerlite`
>    → https://developer.apple.com/account/resources/icloud/list
>
> 3. Add both to your App ID: `com.enes.ledgerlite`
>
> 4. Set `DEVELOPMENT_TEAM` in `project.yml` to your 10-character team ID.
>
> 5. Re-run `xcodegen generate`.
>
> Until then the app runs on Simulator using local SwiftData only.
> CloudKit sync is wired in **Phase 7.5**.

The App Group (`group.com.enes.ledgerlite`) is already configured in both the main app
and widget entitlements. It allows the widget to read the same SwiftData store as the
main app via a shared container URL. This is set up from day one to avoid a painful
Phase 8 retrofit.

## Architecture

MVVM + SwiftData. Views → ViewModels → Repositories → SwiftData.
ViewModels → Services → Network. Money is always `Int` (minor units).

| Layer | Path |
|-------|------|
| Models | `LedgerLite/Models/` |
| Views | `LedgerLite/Views/` |
| ViewModels | `LedgerLite/ViewModels/` |
| Services | `LedgerLite/Services/` |
| Repositories | `LedgerLite/Repositories/` |
| Utilities | `LedgerLite/Utilities/` |
| Widget | `LedgerLiteWidget/` |
| Tests | `LedgerLiteTests/` |

## Build phases

- [x] Phase 0 — Project scaffolding
- [x] Phase 1 — Data models + Money type
- [x] Phase 2 — Currency service (Frankfurter + fallback)
- [x] Phase 3 — Today tab + Quick Add sheet
- [ ] Phase 4 — Subscriptions tab
- [ ] Phase 5 — Subscription auto-detection
- [ ] Phase 6 — Insights tab (Swift Charts)
- [ ] Phase 7 — Settings + CSV export
- [ ] Phase 7.5 — CloudKit sync
- [ ] Phase 8 — Widget + Siri / App Intents
- [ ] Phase 9 — Polish (empty states, a11y, haptics)

## Notes

- All money is stored as `Int` (minor units). `Double` is never used for money.
- All async work uses structured concurrency (`async/await`, `Task`, `TaskGroup`).
- User-facing strings use `String(localized:)` throughout (localization-ready).
- Logging uses `os.Logger` per subsystem; `print()` is banned.
