# App Store Listing — Ledger Lite

## Name
Ledger Lite – Expense Tracker

## Subtitle (30 chars)
On-Device Scanner, No Account

## Promotional Text (170 chars)
Scan receipts on-device — nothing uploaded, ever. Get a daily safe-to-spend target from your budgets. No account, no cloud, no tracking.

## Category
Finance

## Developer / Seller
Inkbar

## Privacy Policy URL
https://tqakdev.github.io/ledgerlite-privacy/

## Support URL
https://tqakdev.github.io/ledgerlite-privacy/

## Keywords (100 chars)
receipt scanner,safe to spend,on-device ocr,subscriptions,budgets,no account,multi-currency,private

## Description
Ledger Lite is a privacy-first expense tracker built on three ideas most apps don't combine: receipts scanned entirely on your device, a daily safe-to-spend number calculated from your own budgets, and zero servers — ever.

**Receipt scanning with Apple's Vision framework — nothing leaves your iPhone**
Point the camera at a paper receipt or import a screenshot. Ledger Lite uses Apple's on-device OCR (Vision) to extract the total, merchant, date, and a suggested category in seconds. No image is uploaded. No account is required to scan. Cloud-based OCR, a staple of most receipt apps, is architecturally impossible here.

**Daily Safe-to-Spend**
Set monthly budgets per category. Ledger Lite subtracts what you've spent so far this month and divides the remaining budget across the days left — giving you a single "safe to spend today" number on the Today screen. It's proactive guidance, not just a scorecard.

**Subscription auto-detect**
Paste a billing email or SMS confirmation and Ledger Lite extracts the service name, amount, currency, and billing cycle automatically. Your inbox becomes your subscription tracker.

**Historically accurate multi-currency**
Exchange rates are frozen at the moment you log an entry. Past totals never drift when rates change — a correctness guarantee most multi-currency apps skip.

**What's inside:**
• On-device receipt scanner (Apple Vision, camera + photo library, no upload)
• Daily Safe-to-Spend chip — budget ÷ days remaining, shown on Today
• Subscription auto-detect — paste a billing message, get a filled-in subscription
• Today view — daily total with velocity badge (vs. your 30-day average) and streak counter
• Budgets — monthly limits per category with 80 % and 100 % local notifications
• Insights — interactive donut chart and daily/monthly bar chart for any period
• History — swipe by day, full-text search, monthly running total
• Multi-currency — live rates via Frankfurter; amounts frozen at entry for accuracy
• Home screen & Lock Screen widget — daily total at a glance
• Biometric lock — Face ID / Touch ID
• Siri Shortcuts — log an expense or check your total with your voice
• CSV export — one tap
• On-device only — SwiftData, no iCloud, no backend, no tracking

No ads. No account. No data collection.

## What's New (Version 1.0)
Initial release — on-device receipt scanning, Daily Safe-to-Spend, subscription auto-detect, multi-currency with frozen exchange rates, and zero data collection.

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
- Notes: "All data is stored on-device; no backend. To test receipt scanning,
  point the camera at any printed receipt or tap 'Choose Photo' to pick one —
  all OCR runs on-device. Subscriptions, budgets, and Insights populate as
  expenses are added."

## Screenshots
6.9" iPhone set (1320×2868, RGB, no alpha) ready in `.lazyweb/appstore-shots/final/`:
01-today · 02-scan · 03-insights · 04-subscriptions · 05-settings. Upload to the
iPhone 6.9" slot; App Store Connect scales it to smaller devices.

## Pre-submission checklist
- [ ] Privacy Policy / Support URL is LIVE (https://tqakdev.github.io/ledgerlite-privacy/)
- [ ] Accept Free Apps agreement (Agreements, Tax, and Banking)
- [ ] Automatically manage signing enabled for app + widget targets
- [ ] Archive in Xcode → Distribute → upload; attach processed build
- [ ] Real-device smoke test: receipt scan, Face ID lock, widget, deep links
