# Contributing to LedgerLite

Thanks for your interest in contributing!

## Setup

LedgerLite is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) project.

```bash
brew install xcodegen
xcodegen generate
open LedgerLite.xcodeproj
```

Edit `project.yml` (not the generated `.xcodeproj`/`Info.plist`) and re-run
`xcodegen generate` when project settings change.

## Tests

Run the suite before opening a PR:

```bash
xcodebuild -project LedgerLite.xcodeproj -scheme LedgerLite \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Guidelines

- Keep money as integer minor units — never `Double`.
- Views talk to ViewModels; nothing below the ViewModel layer imports SwiftUI.
- Add tests for new logic; keep the suite green.
