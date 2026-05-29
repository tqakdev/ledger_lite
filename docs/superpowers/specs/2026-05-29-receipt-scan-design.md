# Receipt Scan → Quick Add (v1)

**Date:** 2026-05-29
**Status:** Design — awaiting review
**Headline feature for:** next LedgerLite update

## Problem

Every expense in LedgerLite is typed in by hand. The entire value loop —
Today total, Insights, Budgets, Subscriptions — is downstream of capture, and
manual capture is the weakest link and the #1 reason people abandon expense
trackers. The subscription **Auto-detect** feature already proves the model
users like: feed in raw text, get structured fields back. Receipt scanning
applies that same idea to the camera, with zero typing.

## Goal

Let a user log an expense by pointing the camera at a paper receipt — or by
picking a screenshot of a digital receipt — and confirming a pre-filled form.
All processing on-device. No cloud, no accounts. This strengthens, rather than
strains, the app's privacy-first identity.

### Success criteria

- A common receipt (café, grocery, restaurant) scans into a Quick Add form
  with **amount, merchant, date, and a suggested category** already filled.
- A failed or empty scan degrades gracefully to a normal (empty) Quick Add —
  the user never hits a dead end.
- Nothing leaves the device. No network call is involved in scanning.
- `ReceiptTextParser` logic is covered by unit tests against a corpus of real
  receipt text, consistent with the existing `AutoDetectTests` style.

## Scope

**In scope (v1):**

- Live camera capture of paper receipts (`VNDocumentCameraViewController`).
- Photo-library import of existing receipt images (`PhotosPicker`).
- On-device OCR (Vision `VNRecognizeTextRequest`, accurate mode).
- Extraction of: total amount, currency, merchant, date.
- Smart category guess: the user's own history first, keyword map fallback.
- Pre-filling the existing `ExpenseFormSheet` in `.add` mode.
- New `ExpenseSource.scanned` so scanned entries are honestly tagged.

**Out of scope (future):**

- Line-item splitting (one receipt → multiple categorized expenses).
- Storing the receipt image on the `Expense` (v2 — clean add later).
- A "Scan receipt" App Intent / Shortcut for the Action Button.
- **Safe-to-Spend** proactive budgeting — the natural v2 that consumes this
  richer data.

## Architecture

Follows the existing layered MVVM. Views talk to ViewModels; ViewModels call
Services/Repositories; nothing below the ViewModel imports SwiftUI; nothing in
the parser imports Vision.

| Unit | Layer | Responsibility | Depends on | Tested |
|------|-------|----------------|------------|--------|
| `ParsedReceipt` | Models | Value type holding the extracted fields + per-field confidence | Foundation | — |
| `ReceiptTextParser` | Services | **Pure** `static parse(_ text: String) -> ParsedReceipt`. Heuristics for total / currency / date / merchant | Foundation only | ✅ unit |
| `ReceiptScanner` | Services | Thin Vision wrapper: `recognizeText(in: CGImage) async throws -> String` | Vision | — (OCR boundary) |
| `MerchantCategoryGuesser` | Services | Guess a category name from a merchant string | `ExpenseRepository` (history) | ✅ unit |
| `ReceiptScanView` + `DocumentScannerRepresentable` | Views | Camera + `PhotosPicker` entry; orchestrates scanner → parser → guesser → produces `ParsedReceipt` | SwiftUI, VisionKit | — |
| `ExpenseFormViewModel.applyParsedReceipt(_:)` | ViewModels | Mirror of `applyTemplate()`: set fields, resolve guessed category, set `lowConfidence` flag | — | ✅ unit |

### `ParsedReceipt`

```
struct ParsedReceipt {
    var amountMinor: Int?
    var currencyCode: String?
    var merchant: String?
    var date: Date?
    var suggestedCategoryName: String?
    var rawText: String
    // Per-field confidence so the form can decide what to pre-fill vs. flag.
    var amountConfident: Bool
}
```

### `ReceiptTextParser` (the testable core)

Pure function, no I/O. Heuristics:

- **Total:** scan lines for total keywords (`total`, `amount due`, `balance`,
  `grand total`, localized variants); prefer the currency-like number on/near a
  total line; fall back to the largest currency-like number in the lower
  portion of the receipt. Parse into minor units with the existing
  `Money` / `AmountInputParser` conventions.
- **Currency:** reuse `SubscriptionDetector`'s symbol→code map
  (`$`→USD, `€`→EUR, …). Default to the user's home currency if no symbol found.
- **Date:** `NSDataDetector` (`.date`); choose the most recent past date if
  several; default to `.now` if none.
- **Merchant:** the most prominent top-of-receipt line that is not an address,
  phone number, or currency/total label (reuse `SubscriptionDetector.noiseWords`
  thinking).

Each heuristic is independently testable. OCR is deliberately **not** inside
this unit, so the logic is fully covered without needing real images.

### `MerchantCategoryGuesser`

```
func guessCategoryName(forMerchant merchant: String) -> String?
```

1. **History first (personalized, private):** look up the most recent past
   expense whose merchant matches (case-insensitive, normalized), return its
   category name. This learns from the user's own behavior with zero config.
2. **Keyword fallback:** a small built-in map of merchant tokens → category
   (e.g. `coffee/café/starbucks/pret` → Food, `uber/lyft/shell/bp` →
   Transport, `netflix/spotify` → Entertainment). Returns `nil` if no match,
   in which case the form keeps its existing default ("Other").

### Capture flow

1. `ReceiptScanView` offers two actions: **Camera** and **Photo**.
2. Camera path uses `VNDocumentCameraViewController` (auto edge-detection,
   multi-page → take page 1 in v1). Photo path uses `PhotosPicker`.
3. The chosen image's `CGImage` → `ReceiptScanner.recognizeText` →
   `ReceiptTextParser.parse` → `MerchantCategoryGuesser` fills
   `suggestedCategoryName` → a `ParsedReceipt`.
4. Dismiss the scanner and present `ExpenseFormSheet(mode: .add)` with the
   parsed receipt applied.

### Entry points

- **Today screen:** a camera **mini-FAB** stacked above the existing `+` FAB
  (`FABView`). Same visual language, secondary size/weight. Routed through a
  new `TodaySheet` case (e.g. `.scanReceipt`) set by a
  `TodayViewModel.presentScan()` method, parallel to `presentQuickAdd()`.
- **Quick Add sheet:** a "Scan receipt" button at the top of
  `ExpenseFormSheet`, so users who open manual add still discover scanning and
  can switch to it.

### Pre-fill behavior

`ExpenseFormViewModel.applyParsedReceipt(_:)`:

- Sets `currencyCode`, `merchant`, `date` when present.
- Sets `amountString` / `minorUnits` **only when `amountConfident`** — otherwise
  leave the amount blank rather than pre-fill a wrong number.
- Resolves `suggestedCategoryName` to an actual `Category`; if unresolved,
  keep the current default.
- Sets a `lowConfidence` flag when the amount was uncertain so the sheet can
  show a quiet caption: "Scanned — double-check the amount."

## Data model change

Add a case to `ExpenseSource` (`LedgerLite/Models/Enums.swift`):

```
case scanned = "scanned"
```

`Expense.source` is set to `.scanned` by the scan-originated add path. Stored
as raw `String`, so this is additive and backward-compatible — existing rows
remain `manual` etc.

## Error handling

- **OCR throws / returns empty:** present the Quick Add form empty with a brief
  note; never lose the user's intent.
- **Parse finds no amount:** open the form with whatever was found (merchant /
  date / category), amount blank, `lowConfidence` caption shown.
- **Camera permission denied:** show a `ContentUnavailableView`-style message
  with a Settings deep link; the photo-import path still works.
- **No category resolved:** fall back to existing default selection logic.

## Privacy & permissions

- All scanning is on-device (Vision). No network in the scan path.
- v1 does **not** persist the receipt image — only extracted fields.
- Add `NSCameraUsageDescription` to the app target's Info plist via
  `project.yml` (per the build workflow: edit `project.yml`, then
  `xcodegen generate` — never hand-edit the pbxproj/Info.plist).
- `PhotosPicker` (PHPicker) requires no usage-description string.

## Testing

New test files alongside the existing suite (114 tests today):

- `ReceiptTextParserTests` — corpus of representative receipt text:
  café, grocery, sit-down restaurant, foreign-currency, and noisy/garbled OCR.
  Assert extracted total (minor units), currency, date, merchant, and that
  ambiguous receipts set `amountConfident = false`.
- `MerchantCategoryGuesserTests` — history-hit, keyword-hit, and no-match cases.
- `ExpenseFormViewModelTests` (extend) — `applyParsedReceipt` sets fields,
  honors the confidence gate, resolves/falls back category, sets `lowConfidence`.

OCR and the camera controller are not unit-tested (UIKit/Vision boundary);
correctness lives entirely in the pure parser and guesser.

## Open questions

None blocking. Multi-page receipts collapse to page 1 in v1; revisit if needed.
