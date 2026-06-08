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
• Runway (home) — a forward balance forecast with a daily "truly safe to spend" that accounts for upcoming bills, and a balance-to-payday chart showing the day you'd dip
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
Meet Payday Runway: a forward-looking forecast that tells you what's truly safe to spend today after your upcoming bills — calculated entirely on your device, with no bank login. Plus on-device receipt scanning, subscription auto-detect, and multi-currency with frozen rates.

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
Lead with the differentiator. Recommended 6.9" iPhone set (1320×2868, RGB, no alpha):
01-runway (the home screen: "truly safe to spend / day" + balance-to-payday chart —
the FIRST screenshot) · 02-bills (recurring charges feeding the runway) · 03-scan
(on-device OCR) · 04-spending (day log) · 05-trends (heatmap). Capture with the
`--seed-screenshots` launch arg, which pre-fills a balance + payday so the runway
renders. The runway shot is the one a reviewer must see in the first 15 seconds —
it is visually unlike any other expense app.

## Pre-submission checklist
- [ ] Privacy Policy / Support URL is LIVE (https://tqakdev.github.io/ledgerlite-privacy/)
- [ ] Accept Free Apps agreement (Agreements, Tax, and Banking)
- [ ] Automatically manage signing enabled for app + widget targets
- [ ] Capture NEW screenshots leading with the Runway card + projection chart
- [ ] Archive in Xcode → Distribute → upload; attach processed build
- [ ] Real-device smoke test: set up runway, receipt scan, Face ID lock, widget
