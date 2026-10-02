# Copper Kit

A personal organiser for home-workshop tools and portable kits. Catalogue drills, clamps, measuring tools and
cases; give each a home location; build a kit for a job; record a checkout for personal use or a loan; take a
partial return; and send damaged units straight to **Needs Service** so they are never offered as available.

One quantity ledger drives every screen — **Available · In Use · On Loan · Needs Service** — so no card keeps
its own number. No consumables, shop, rental payments, deposits, recognition or valuations. A purchase cost is an
optional private note.

* Minimum iOS **15.0**, iPhone, SwiftUI. No third-party dependencies, no network, no account, no analytics.
* Architecture: **Clean** — see [Docs/Architecture.md](Docs/Architecture.md).

## Build and run

```bash
open CopperKit.xcodeproj
```

Choose the **CopperKit** scheme and an iPhone simulator, then Run. From the command line (this Mac has the
Command Line Tools selected, so point `DEVELOPER_DIR` at Xcode):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CopperKit.xcodeproj -scheme CopperKit -destination 'platform=iOS Simulator,name=iPhone 16' build
```

The first launch shows three onboarding pages and then an **empty** Home — no demo tools, no invented value.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CopperKit.xcodeproj -scheme CopperKit -destination 'platform=iOS Simulator,name=iPhone 16' test
```

* `CopperKitTests` (39 tests) — the ledger and every rule: individual = 1 unit, Adjust Stock only from
  Available with a reason, tracking mode locked after the first movement, delete vs archive, archive blockers,
  all-or-nothing checkout, idempotent confirm (same operation id → one handover), merged duplicate lines,
  Personal Use vs Loan counts, back-dated checkout already Overdue, partial return with damage → service record,
  return idempotency and validation, lost units, service return/write-off, inventory gains/losses as separate
  events, location deletion with reassignment (archived included), kits (unique tools, Needs Review, duplicate
  copies needs only), preparation never reserving and losing Ready when stock moves, run-only replacements and
  Update Template, repeat copies needs not dates, cost Unknown vs explicit zero, file round trip, newer-format
  file left untouched, unreadable file kept aside, older file degrading field by field, CSV formula guarding.
* `CopperKitUITests` — `testAcceptanceFlowFromEmptyWorkshop` walks onboarding → empty Home → Add Tool with an
  inline new location → Tool Detail → Loan checkout → partial return with one damaged unit → Home → Service.
  `testScreenTour` visits every section with a seeded workshop.

UI tests use DEBUG-only launch arguments: `-uiTestReset` (isolated empty store), `-skipOnboarding`,
`-uiTestSeed` (a small sample workshop for the tour). None exist in release builds. Set
`TEST_RUNNER_CK_SHOTS=<folder>` to have the UI tests write their screenshots there.

## How the numbers work

* **Total** comes only from stock movements: initial quantity, Adjust Stock, inventory differences, lost units,
  write-offs. **In Use / On Loan** is what open handovers still hold; **Needs Service** is what open service
  records hold; **Available** is the rest. Home's *Tool Records* counts cards, *Units* counts physical things,
  *Overdue Handovers* counts handovers, not tools.
* **Preparation** ticks never move stock and never reserve anything. A prepared line that stops being available
  (someone else took the drill) shows *Needs Review* and loses Ready. Replacements and reduced quantities belong
  to the run until **Update Template** is pressed.
* **Confirm Checkout** re-checks availability and moves every line in one transaction, or none. Each review
  screen carries one operation id, so a double tap cannot hand out a second kit. Started At may be in the past;
  a Due At in the past makes the handover Overdue at once. Due dates keep the time zone they were entered in.
* **Confirm Return** is line by line: *Back to Available*, *Needs Service* (opens a service record with the issue)
  or *Lost* (leaves the total, after a confirmation). While anything is outstanding the handover stays open and
  can go Overdue; when everything is back it is *Returned* and its history stays.
* **Inventory Check** compares counts with *At Home = Available + Needs Service*; each difference is a separate
  inventory movement and the check itself is kept.
* **Archive** needs In Use, On Loan and Needs Service at zero — otherwise the exact open items are listed.
  Archived tools keep history and aren't offered in new kits or checkouts. A tool with no history can be deleted;
  **Delete All Data** in Settings removes everything.
* **Private Purchase Cost** is for the whole batch on the purchase date; empty means *Unknown*, and zero needs the
  explicit *Enter Zero*. It is hidden on the tool page until *Show Cost*, and never totalled.

## Privacy and permissions

* Everything is stored in Application Support (`CopperKit/workshop.json` + `Photos/`), written atomically with
  file protection. A file from a newer version is left untouched (read-only mode); an unreadable file is moved
  aside, never overwritten.
* Photos come from the system picker (no library permission) or the camera (asked only on *Take Photo*); they are
  re-encoded at 1600 px and metadata is dropped.
* Due-date reminders are local notifications for the owner only, requested only when switched on. The app never
  reads Contacts and never messages the people you lend to.
* `PrivacyInfo.xcprivacy` declares no tracking and no collected data (UserDefaults reason CA92.1 for the
  onboarding flag).

## Artwork

`ck01`–`ck12` in `Assets.xcassets` plus the app icon, rendered procedurally by `Tools/ArtGen` (see its README);
prompts for regenerating them with an image model are in `Docs/AssetPrompts.md`. Illustrator art can replace
them with `Tools/convert_webp_art.sh <folder>`.

## Known limits

* Verified on the iOS 18.5 simulator (iPhone 16). The deployment target is 15.0 and only iOS 15 APIs and SF
  Symbols are used, but no iOS 15 runtime was available to run it on.
* iPhone only, portrait, light appearance (the working background is fixed at #F8F3E9 by the brief).
* The brief's text for screens 12–17 was cut off; Handovers (12), Partial Return (13), Service (14), Inventory
  Check (15), History (16) and Settings (17) were built from the user flow and the rules stated elsewhere.
