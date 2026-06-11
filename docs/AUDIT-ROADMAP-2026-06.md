# LedgerLite — Audit & Roadmap

*Session: June 11, 2026 · branch `audit/e2e-improvement` · suite grew 164 → 186 tests, all green*

## 1. Current state

**Architecture** — SwiftUI + SwiftData (iOS 17+), MVVM with thin repositories, XcodeGen-managed project. Three layers hold financial logic: pure engines (`Money`, `RunwayForecast`, parsers — excellent test coverage), `@MainActor` services (currency, subscriptions — good coverage), and view models (partial coverage). A widget extension shares the store via App Group; Siri/Shortcuts intents open their own containers against the same store.

**Verified working** (every claim backed by a command run this session):
- Build + full test suite: 186/186 across 45 suites.
- All four tabs render with seeded data; on-screen financial math hand-verified (bills total, runway window filtering, floor-division safe-per-day, "left today").
- Receipt scan → form prefill → category guess (demo-receipt path; the document camera cannot run in the Simulator).
- Deep links `today/bills/runway/settings/scan` route correctly (scan fixed this session, both warm and cold tab states).
- Money invariants: minor-unit ints everywhere, Decimal-only arithmetic, sum-then-round-once policy now enforced through a single canonical helper.

**Not exercisable in this environment** — needs one manual device pass:
- Face ID lock + the new app-switcher privacy cover.
- Real-camera OCR scanning.
- Notification delivery (billing reminders, budget alerts).
- CSV export share-sheet UX (logic is unit-tested; the sheet itself is not).

**Fragile areas:**
- **Home-currency change is unsound (B5, deferred):** switching home currency re-labels every historical total without converting. `homeCurrencyAtEntry` snapshots make the data model *capable* of correct re-homing, but no code performs it.
- **CSV re-import duplicates rows:** import has no dedup key, so restoring a backup into a non-empty store doubles every expense.
- **No UI test target.** All 186 tests are unit-level; regressions in view wiring (like the scan deep-link bug) are only catchable manually.
- **CloudKit-readiness is partial:** uniqueness is enforced in repositories only (correct for CloudKit), but there is no merge/conflict story yet.

## 2. Fixed this session

| Commit | Fix | Test evidence |
|---|---|---|
| `cfdd97e` | Bills tab silently discarded missed billing cycles (advanced dates without generating expenses; raced launch pass). Also coalesced concurrent generation passes that could double-book a cycle. | 0→2 expenses recorded; 2→1 duplicate eliminated |
| `f264bad` | Zero/garbage exchange rate could be cached and poison all cross-rates for the UTC day. | zero no longer cached |
| `a9ffeaa` | `rehydrateStaleRates()` was fully tested but never called — offline expenses kept a placeholder 1:1 rate forever. Now runs at launch. | existing rehydrate suite |
| `6c1a41e` | `ledgerlite://scan` did nothing unless the Runway tab was already visible. | reproduced + verified fixed in Simulator, both states |
| `ee23902` | Siri "log $15" without a category saved uncategorized while claiming "logged in Other". | 4 new resolution tests |
| `49679a1` | Foreign-currency subscription bills entered the runway at face value (¥1,000 counted as $10.00) — future dates never hit the rate cache. | 1000→1100 minor units |
| `5ee3002` | CSV logic extracted from SettingsView into testable `ExpenseCSV` (behavior-preserving). | suite green pre/post |
| `a55da6d` | CSV export dropped notes entirely; dates shifted a day for users west of UTC (export and import both). | 7 new format tests |
| `a57fc0c` | "Reset All Data" left merchant names + amounts in the system Spotlight index and stale safe-to-spend feeding the widget. | — (system-framework glue) |
| `cf1d7f4` | App-switcher snapshot showed balances with lock enabled (cover now shown when scene leaves `.active`). | — needs device verification |
| `629806c` | Home-currency conversion deduplicated from 5 drifting implementations into `Expense.homeMinorDecimal`. | 6 characterization tests pinned behavior first |

## 3. Deferred (and why)

| Issue | Why deferred |
|---|---|
| **B5 — home-currency change doesn't re-home history.** Totals mix old-home minor units into new-home sums at face value. | Product decision needed: (a) re-home in place via historical rates (`needsRateRefresh` + rehydrate machinery already supports this), or (b) keep amounts immutable and convert at display time. (a) is simpler and matches the current frozen-rate design; (b) is more auditable. **Recommend (a).** |
| CSV import has no dedup → restore doubles data | Needs a decision on identity (export `id` column vs. fuzzy date+amount+merchant hash). Export format change → do together with B5 era of "data trust" work. |
| `RunwayForecast.Bill.id` collides for two same-name/amount/day bills | Cosmetic ForEach risk only; trivial but zero observed impact. |
| Subscription generation uses UTC day boundary; Bills due "today" record a day late west of UTC | Behavior is consistent and self-correcting; fixing alone risks double-generation for existing users. Bundle with a deliberate date-handling pass. |
| Payday == today shows a 1-day runway instead of the "payday arrived" prompt | Design choice; verify intended copy first. |

## 4. Optimization opportunities (impact ÷ effort, best first)

1. **Today-tab refresh does 4 broad fetches per appear** (streak: 366 days; daily average: 30 days; safe-to-spend: month; budget alerts: month again) — all on the main actor, re-triggered by every sheet dismissal. Consolidate into one 366-day fetch deriving all four metrics. *Impact: M (scales with data), Effort: S.*
2. **Global search loads every expense into memory** then filters. Use `#Predicate` `localizedStandardContains` + `fetchLimit`. *Impact: M for multi-year datasets, Effort: S.*
3. **`Money.formatted()` builds a `NumberFormatter` per call** — hot in lists/widgets. Cache per (currency, locale) like `Money.symbol` already does. *Impact: S–M, Effort: S.*
4. **`WidgetDataService` opens a fresh `ModelContainer` per timeline refresh.** Cache statically. *Impact: S, Effort: S.*
5. **Insights heatmap re-fetches 91 days independently of the period fetch** — merge when period ⊇ heatmap window. *Impact: S, Effort: S.*

## 5. Security & privacy posture

- **Good:** no secrets in repo (`Local.xcconfig` gitignored, template committed); HTTPS-only, keyless rate APIs with validated decoding; os_log default redaction keeps amounts/merchants private in release logs; camera/Face ID usage strings honest; `PrivacyInfo.xcprivacy` present; screenshot/demo hooks are `#if DEBUG`.
- **Strengthened this session:** Spotlight wipe on reset; app-switcher snapshot cover; zero-rate rejection.
- **Watch:** runway balance lives in plaintext App Group `UserDefaults` (P2: Keychain or accept as device-local); lock uses `.deviceOwnerAuthentication` (passcode fallback — reasonable, but document it); widget timelines show balances on the lock screen by user opt-in.

## 6. Prioritized next steps

**P0 — data trust**
1. Decide + implement home-currency re-homing (B5) — *every total is wrong after a currency switch; ~1–2 days using the existing rehydrate path.*
2. CSV import dedup + export `id` column — *restore-from-backup currently corrupts the store; ~½ day with format tests.*
3. One manual device QA pass (Face ID lock + snapshot cover, camera scan, both notification types) — *several fixes are Simulator-unverifiable; ~1 hour.*

**P1 — robustness & speed**
4. Today-refresh fetch consolidation (opt. #1) — *biggest perceived-performance win; ~½ day.*
5. XCUITest smoke pack: add → edit → delete → scan-prefill → export — *the only bug class this session's fixes couldn't regression-protect; ~1–2 days.*
6. Search predicate pushdown (opt. #2) — *~2 hours.*
7. Date-handling pass: UTC vs local day for billing generation + payday-today semantics — *bundle the two deferred date items; ~1 day.*

**P2 — polish & future-proofing**
8. `Money.formatted()` formatter cache; widget container reuse (opts. #3–4).
9. Keychain for runway balance/payday.
10. Pre-CloudKit audit: document uniqueness invariants, design merge policy (prep for the Phase 7.5 iCloud entitlements already scaffolded in `project.yml`).

## 7. Suggested milestone path

**M1 — "Trustworthy data" (~1–2 weeks):** all P0 items + P1 #5 (UI smoke pack). Exit: a user can switch home currency, restore a backup, and lock the app — and every number is still right. This is the bar a finance app must clear before growth features.

**M2 — "Sync" (~2–4 weeks):** CloudKit private-database sync (paid developer account, entitlements already drafted), merge policy from the P2 #10 audit, plus the P1 performance items so sync-sized datasets stay fast. Exit: two devices converge on the same ledger.

**M3 — "Deepen the moat" (ongoing):** receipt-scanner accuracy loop (grow the fixture corpus from real receipts, track parse-rate as a metric), subscription price-change detection ("Netflix went up $2"), what-if scenarios saved as plans. These compound the on-device/no-bank-login identity that differentiates the app.

---
*Maintenance note: `project.pbxproj` is regenerated by `xcodegen generate` and force-added (`git add -f`); the cosmetic `lastKnownFileType` churn from the newer XcodeGen landed with `ee23902`.*
