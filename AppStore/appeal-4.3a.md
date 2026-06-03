# App Store Connect Appeal — Guideline 4.3(a) Spam
Submission ID: 7ef0208a-df4f-40da-9718-bbba845cdb74

---

## Message to paste in App Store Connect

Hello App Review Team,

Thank you for reviewing Ledger Lite. We understand the concern raised under
Guideline 4.3(a) and want to explain what makes this app meaningfully different
from other expense trackers.

**1. On-device receipt scanning using Apple's Vision framework**

Most receipt-scanning apps upload images to a cloud OCR service (e.g.
Google Vision, Azure Cognitive Services, or a proprietary backend). Ledger Lite
uses Apple's on-device `VNRecognizeTextRequest` exclusively. No image ever
leaves the device, no network request is made during a scan, and the feature
works fully offline. This is a deliberate architectural decision that is both
technically distinct and clearly visible to users. To verify: connect a device
to Airplane Mode, scan a receipt — it works exactly the same.

**2. Daily Safe-to-Spend**

Ledger Lite computes a single "safe to spend today" number on the Today screen:
it takes the user's total monthly budget across all categories, subtracts
month-to-date spending (converted to home currency with frozen exchange rates),
and divides by the days remaining in the month. This turns a backward-looking
budget tracker into a forward-looking daily spending guide. We are not aware of
a free, no-account iOS app that surfaces this calculation.

**3. Subscription auto-detect from unstructured text**

Users can paste any billing email or SMS confirmation into a text field, and the
app extracts the service name, amount, currency, and billing cycle automatically
using a custom heuristic parser (no API call, no cloud). This is distinct from
apps that require manual subscription entry or read directly from bank feeds.

**4. Historically accurate multi-currency accounting**

Exchange rates are frozen at the exact moment each expense is logged
(`exchangeRateToHome` stored on the `Expense` entity). Historical totals never
drift when rates change — a correctness property that most multi-currency apps
sacrifice for simplicity.

**5. Genuinely zero-backend**

Ledger Lite has no server, no iCloud sync, no Firebase, and no analytics SDK.
All data is stored in SwiftData in the app's sandbox. This is not "optional
cloud sync turned off" — it is structurally impossible for the app to transmit
user data. The source code is open at https://github.com/tqakdev/ledger_lite if
the review team would like to verify any of the above claims.

We believe these five properties — individually and especially in combination —
constitute a distinct app that cannot reasonably be described as a repackage of
an existing template. We welcome specific feedback on which aspect of the binary
or metadata triggered the similarity flag so we can address it directly.

Thank you for your time.

---

## Notes for the developer

- Paste the "Message to paste" section verbatim into the App Store Connect
  reply field under the 4.3(a) resolution thread.
- The GitHub link is already public; confirm before submitting.
- If Apple asks for a demo video, record: (a) Airplane Mode receipt scan,
  (b) Safe-to-Spend chip changing after adding an expense, (c) paste-to-detect
  subscription flow.
- After sending the appeal, also update the listing with the revised description
  in listing.md before resubmitting the binary.
