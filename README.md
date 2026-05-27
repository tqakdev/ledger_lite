# LedgerLite

A clean, privacy-first expense and subscription tracker for iOS. Built with SwiftUI and SwiftData — no accounts, no cloud required.

## Features

- **Quick Add** — log an expense in seconds with a large amount field, category picker, merchant suggestions, and quick-add templates
- **Today view** — see today's total, compare against your 30-day daily average, and swipe to edit or delete
- **History** — browse by day with date navigation and full-text search across all expenses
- **Subscriptions** — track recurring bills, see your estimated monthly cost, pause/resume/cancel, and get renewal reminders
- **Auto-detect** — paste a billing email or SMS and let the app extract subscription details automatically
- **Insights** — spending by category (donut chart), daily/monthly trends (bar chart), budget progress, and top merchant — across week, month, year, or all time
- **Multi-currency** — live exchange rates via Frankfurter; amounts stored in minor units so rounding is exact
- **Widget** — Today total on your Home Screen or Lock Screen
- **CSV export** — one tap to export all expenses
- **Budgets** — set monthly limits per category; get notified when you approach or exceed them

## Requirements

- iOS 17.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Getting started

```bash
git clone https://github.com/bluemadisonblue/ledger_lite.git
cd ledger_lite
xcodegen generate
open LedgerLite.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and is not committed to version control. Run `xcodegen generate` whenever `project.yml` changes.

### Run on your iPhone (free Apple ID)

1. Xcode → **Settings → Accounts** → sign in with your Apple ID.
2. **LedgerLite** target → **Signing & Capabilities** → **Automatically manage signing** → set Team to your Personal Team.
3. Repeat for the **LedgerLiteWidget** target.
4. Select your iPhone and press **⌘R**.

If signing fails on **App Groups**, register `group.com.enes.ledgerlite` in the [Developer Portal](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) (free accounts can create App Group IDs), then click **Try Again** in Xcode.

## Architecture

MVVM with a clean layered separation: Views talk only to ViewModels; ViewModels call Repositories and Services; nothing below the ViewModel layer imports SwiftUI.

| Layer | Path | Responsibility |
|-------|------|----------------|
| Models | `LedgerLite/Models/` | SwiftData entities (`Expense`, `Category`, `Subscription`) |
| Views | `LedgerLite/Views/` | SwiftUI screens and components |
| ViewModels | `LedgerLite/ViewModels/` | `@Observable` + `@MainActor`; owns UI state |
| Repositories | `LedgerLite/Repositories/` | SwiftData fetch/insert/delete |
| Services | `LedgerLite/Services/` | Currency rates, notifications, Spotlight, CSV |
| Utilities | `LedgerLite/Utilities/` | `Money` type, `UserPreferences`, extensions |
| Widget | `LedgerLiteWidget/` | WidgetKit extension |
| Tests | `LedgerLiteTests/` | Unit tests for models, ViewModels, services |

**Key design decisions:**

- All money is stored as `Int` (minor units, e.g. cents). `Double` is never used for monetary values.
- Exchange rates are frozen at entry time (`exchangeRateToHome`) so historical totals never drift.
- `@Observable` macro throughout — no `ObservableObject`, no `@Published`.
- All async work uses structured concurrency (`async/await`, `Task`). No Combine.
- User-facing strings use `String(localized:)` — localization-ready.
- Logging uses `os.Logger` per subsystem.

## CloudKit sync (future)

iCloud sync via CloudKit is planned. To enable it on a paid Apple Developer account:

1. Register the App Group `group.com.enes.ledgerlite` in the Developer Portal.
2. Register the CloudKit container `iCloud.com.enes.ledgerlite`.
3. Add both to the App ID `com.enes.ledgerlite`.
4. Set `DEVELOPMENT_TEAM` in `project.yml` to your 10-character team ID.
5. Re-run `xcodegen generate`.

The App Group is already wired in both the app and widget entitlements so the widget can read the same SwiftData store via a shared container URL.

## License

MIT
