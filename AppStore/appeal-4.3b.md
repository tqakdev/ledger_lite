# App Store Connect Appeal — Guideline 4.3(b) Spam
Submission ID: 7ef0208a-df4f-40da-9718-bbba845cdb74

---

## Message to paste in App Store Connect

Hello App Review Team,

Thank you for reviewing Ledger Lite. We'd like to address the concern raised
under Guideline 4.3(b) and demonstrate that this app offers a meaningfully
different experience from what is already widely available.

We understand that expense-tracking is a crowded category. The five points below
describe capabilities that are technically distinct, verifiable in the binary,
and not found in combination in any free, no-account iOS expense app we are
aware of.

**1. On-device receipt scanning — no cloud, no account, works in Airplane Mode**

Most receipt-scanning apps upload images to a cloud OCR service (Google Vision,
Azure Cognitive Services, or a proprietary backend). Ledger Lite uses Apple's
`VNRecognizeTextRequest` exclusively. No image ever leaves the device. No
network request is made during a scan. The feature is fully functional offline.

To verify: put the device in Airplane Mode and scan a receipt — it works
identically. This is architecturally impossible in cloud-OCR apps.

**2. Daily Safe-to-Spend — a forward-looking budget signal, not a tracker**

The Today screen shows a single number: "Safe to spend today." This is computed
as: (sum of monthly category budgets − month-to-date spending in those
categories) ÷ days remaining in the month. The result converts all multi-
currency expenses to the user's home currency using historically frozen exchange
rates (see point 4).

This turns a backward-looking expense log into a forward-looking daily spending
guide. We are not aware of a free, no-account iOS app that surfaces this
calculation.

**3. Subscription auto-detect from pasted text**

Users paste any billing confirmation email or SMS into a single text field. The
app parses the service name, amount, currency, and billing cycle automatically
using an on-device heuristic parser — no API call, no cloud, no bank feed
access. This input method is structurally different from manual-entry or
open-banking subscription trackers.

**4. Historically accurate multi-currency accounting**

The exchange rate is frozen at the exact moment each expense is logged
(`exchangeRateToHome` stored on the `Expense` entity). Historical totals never
change when rates move — a correctness property most multi-currency apps
sacrifice for simplicity.

**5. 13-week spending heatmap**

The Insights screen includes a GitHub-style contribution graph showing the
user's personal daily spending intensity over the past 13 weeks. Cell colour is
normalised to the user's own peak day, making the pattern immediately legible
without labels or numbers. This visualisation is independent of the selected
period filter, always showing recent activity at a glance.

**6. Genuinely zero-backend architecture**

Ledger Lite has no server, no iCloud sync, no Firebase, and no analytics SDK.
All data lives in SwiftData in the app sandbox. This is not "optional cloud sync
turned off" — it is structurally impossible for the app to transmit user data.
The source is open at https://github.com/tqakdev/ledger_lite for verification.

---

We believe this combination of on-device OCR, a forward-looking daily budget
signal, automatic subscription detection, frozen-rate multi-currency accounting,
and zero-backend architecture constitutes a meaningfully different experience
from other apps in the category. We welcome any specific feedback on which
aspect of the binary or metadata raised the similarity concern.

Thank you for your time and consideration.

---

## Notes for the developer

- Paste the section above verbatim into the App Store Connect Resolution Center
  reply under the 4.3(b) rejection thread.
- The GitHub repository must be public before submitting — confirm at
  https://github.com/tqakdev/ledger_lite.
- If Apple requests a demo video, record these flows:
    (a) Airplane Mode active → scan receipt → fields auto-populate
    (b) Paste billing email → subscription auto-detected with amount + cycle
    (c) Add an expense → Safe-to-Spend chip updates on the Today screen
    (d) Insights tab → 13-week heatmap visible
- Screenshots of (a) and (c) are the highest-value additions to the listing;
  reviewers spend ~15 s per app and visual proof of OCR is hard to dismiss.
- After sending the appeal, also update the listing in App Store Connect with
  the revised copy from listing.md before resubmitting the binary.
