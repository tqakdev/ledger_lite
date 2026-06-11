# Contributing to LedgerLite

Thanks for your interest in contributing!

## Setup

LedgerLite is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) project.

```bash
brew install xcodegen
xcodegen generate
open LedgerLite.xcodeproj
```

Edit `project.yml` (never the generated `.xcodeproj`/`Info.plist` — XcodeGen
overwrites them) and re-run `xcodegen generate` when project settings change.

The generated `project.pbxproj` **is** committed so the repo builds out of the
box. After adding or removing source files, run `xcodegen generate` and commit
the regenerated file — otherwise the build breaks for everyone who didn't run
generate themselves.

## Tests

Run the suite before opening a PR:

```bash
xcodebuild -project LedgerLite.xcodeproj -scheme LedgerLite \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Tip: after **adding** test cases, use `clean test` once — `xcodebuild` can run
a stale test bundle that silently omits new tests.

## Guidelines

- Keep money as integer minor units — never `Double`. Aggregations accumulate
  `Decimal` via `Expense.homeMinorDecimal` and round once at the end.
- Views talk to ViewModels; nothing below the ViewModel layer imports SwiftUI.
- Keep parsing logic (receipts, CSV, subscription detection) pure and
  unit-tested — no Vision/SwiftData/SwiftUI in the heuristics.
- User-facing strings use `String(localized:)`; logging uses `os.Logger`.
- Add tests for new logic; keep the suite green.
