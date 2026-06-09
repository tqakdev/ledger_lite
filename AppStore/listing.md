# App Store Listing — Ledger Lite

## Name
Ledger Lite – Payday Runway

## Subtitle (30 chars)
Forecast your money to payday

## Promotional Text (170 chars)
See what you can really spend today — after the bills already heading your way. A daily safe-to-spend that forecasts to payday. No bank login. Nothing leaves your phone.

## Category
Finance

## Developer / Seller
Inkbar

## Privacy Policy URL
https://tqakdev.github.io/ledgerlite-privacy/

## Support URL
https://tqakdev.github.io/ledgerlite-privacy/

## Keywords (100 chars)
safe to spend,payday,cash flow,forecast,budget,no bank,subscriptions,private,on-device,runway

## Description
Most money apps show you the past — a pile of charts about money you already spent. Ledger Lite shows you the future. It answers the one question that actually causes money stress: "what can I safely spend today and still make it to payday?"

**Your runway to payday**
Enter your available balance and your next payday. Ledger Lite projects your balance forward day by day — subtracting the subscription bills you've already committed to and your recent spending pace — and shows you a single "truly safe to spend" number for today. If your balance is heading for zero before payday, it tells you the day, before it happens.

This is not "budget ÷ days left." It nets out the rent share, the streaming bundle, and the gym fee that hit before your next paycheck — so the number you see is the number you can actually trust.

**No bank login — and that's the point**
Every cash-flow forecaster on the App Store wants your bank password. Ledger Lite forecasts entirely from data you control: the balance you type, the subscriptions you track, and the spending you log. Nothing is linked. Nothing leaves your iPhone. It is structurally impossible for this app to transmit your financial data — there is no server to send it to.

**On-device receipt scanning**
Point the camera at a paper receipt or import a screenshot. Apple's on-device Vision OCR extracts the total, merchant, date, and a suggested category in seconds — fully offline, no upload, no account.

**Subscription auto-detect**
Paste a billing email or SMS and Ledger Lite pulls out the service, amount, currency, and billing cycle automatically — then folds those bills straight into your runway.

**Historically accurate multi-currency**
Exchange rates are frozen the moment you log an entry, so past totals never drift when rates move. Works abroad, fully offline.

**What's inside:**
• Runway (home) — a forward balance forecast with a daily "truly safe to spend" that accounts for upcoming bills, a live today-envelope bar that fills as you spend, and a balance-to-payday chart showing the day you'd dip
• What-if — type a hypothetical spend (say $150) and the runway re-projects instantly: your new safe-to-spend, the daily hit, and whether you'd still make it to payday. On-device, before the money is gone — the answer no bank-linked app can give
• Spending — log expenses by day, full-text search, on-device receipt scanner (Apple Vision, no upload)
• Bills — track recurring charges, paste a billing message to auto-detect, see them netted into your runway
• Trends — spending trend chart, 13-week heatmap, budgets with 80 % / 100 % local alerts
• Multi-currency — live rates; amounts frozen at entry for accuracy, works offline abroad
• Home screen & Lock Screen widget
• Biometric lock — Face ID / Touch ID
• Siri Shortcuts — log an expense or check your total with your voice
• CSV import & export
• On-device only — SwiftData, no iCloud, no backend, no tracking

No ads. No account. No bank linking. No data collection.

## What's New (Version 1.0)
Meet Payday Runway: a forward-looking forecast that tells you what's truly safe to spend today after your upcoming bills — calculated entirely on your device, with no bank login. A live envelope bar tracks today's spending, and a "what-if" simulator shows how a splurge changes your runway before you spend it. Plus on-device receipt scanning, subscription auto-detect, and multi-currency with frozen rates.

## Age Rating
4+ (no objectionable content)

## Price
Free

## App Privacy (Nutrition Label)
**Data Not Collected.** Ledger Lite stores everything on-device (SwiftData), has
no accounts or servers, and transmits no personal data. MetricKit metrics are
logged on-device only (os.Logger). In App Store Connect → App Privacy, answer
"No, we do not collect data from this app."
- Camera: used to scan receipts; images are processed on-device and not stored or collected.
- Face ID / Touch ID: handled by the system (Secure Enclave); not collected.
- Notifications: local only (renewal/budget reminders).

## App Review Information
- Sign-in required: No (the app has no account or login).
- Demo account: Not applicable.
- Notes: "All data is stored on-device; there is no backend and no bank linking.
  The app OPENS on the Runway forecast (its home and core concept). If it shows a
  'Set up your runway' card, tap it, enter any balance (e.g. 600) and a payday ~2
  weeks out, then Save — the home screen then renders a daily 'truly safe to spend'
  figure and a balance-to-payday chart with markers for upcoming bills. Add a few
  recurring charges in the Bills tab (+ or paste a billing email to auto-detect) to
  see them netted out of the forecast. Log/scan expenses from the Spending tab or
  the + / scan buttons; all receipt OCR runs on-device (works in Airplane Mode)."

## Screenshots
Final framed sets are committed under `AppStore/screenshots/` — **6.9"**
(`6.9-inch/`, 1320×2868) and **6.5"** (`6.5-inch/`, 1242×2688), both RGB, no alpha.
Lead with the differentiator. Upload order:

1. **01-runway** — the home screen: "truly safe to spend / day", the live today-envelope
   bar, and the balance-to-payday chart. The shot a reviewer must see in the first 15 seconds.
2. **02-whatif** — the what-if simulator in action ("$150 → new safe-to-spend + you'd still
   make it to payday"). The differentiator no bank-linked app can show — slide 2 on purpose.
3. **03-bills** — recurring charges, netted into the runway.
4. **04-scan** — on-device receipt OCR auto-filling an entry.
5. **05-spending** — the daily expense log with search.

Captured with the `--seed-screenshots` launch arg (pre-fills balance + payday so the
runway renders); slide 2 adds `--whatif 150`, slide 4 uses `--screen scan`. Unframed raw
device captures are in `AppStore/screenshots/raw/`; regenerate the framed PNGs with
`AppStore/screenshots/make_frames.py` (teal gradient + headline + device, via headless Chrome).

## Pre-submission checklist
- [ ] Privacy Policy / Support URL is LIVE (https://tqakdev.github.io/ledgerlite-privacy/)
- [ ] Accept Free Apps agreement (Agreements, Tax, and Banking)
- [ ] Automatically manage signing enabled for app + widget targets
- [x] Capture screenshots leading with Runway + what-if (AppStore/screenshots/ — 6.9" & 6.5")
- [ ] Archive in Xcode → Distribute → upload; attach processed build
- [ ] Real-device smoke test: set up runway, receipt scan, Face ID lock, widget
