# Copper Kit — how the code is arranged

Clean architecture in four folders; dependencies point inwards only.

```
App/           composition root (AppContainer), @main, DEBUG-only UI-test seed
Presentation/  SwiftUI screens, the design system, WorkshopStore and AppRouter
Data/          JSON document + DTOs + mapper, photo files, local notifications
Domain/        entities, the stock ledger, rules, use cases, repository protocols
```

```
App ──▶ Presentation ──▶ Domain ◀── Data
  └──────────────────────────────────▲
```

`Domain` imports Foundation only. `Data` implements `WorkshopRepository`, `PhotoStoring` and
`ReminderScheduling`; `Presentation` sees them only through those protocols (plus
`ObservableWorkshopRepository`, whose conformance is declared in `App/AppContainer.swift`).

## Domain

* `Entities/` — plain value types: `Tool`, `StorageLocation`, `KitTemplate` + `PreparationRun`,
  `Handover` (+ `ReturnRecord`), `ServiceRecord`, `StockMovement`, `InventoryCheck`, `ActivityEvent`, and the
  `Workshop` aggregate. Nothing here is `Codable`.
* `Ledger/StockLedger` — the only place quantities come from. Total = Σ movements; In Use / On Loan = what
  open handovers still hold by mode; Needs Service = open service quantity; Available = the remainder. There
  are no stored counters to drift.
* `Rules/` — field limits, validation helpers and the cost parser (Unknown vs explicit zero).
* `UseCases/` — one class per area (`ToolUseCases`, `HandoverUseCases`, `PreparationUseCases`, …). Every
  change runs inside `repository.transact`, which edits a copy and commits only if the closure returns *and*
  the write succeeds — so a checkout whose third line fails leaves the first two untouched. Idempotency is by
  `operationID` on handovers and returns. Each change appends its `ActivityEvent` in the same transaction,
  with names captured at that moment.

## Data

* `WorkshopDTO` mirrors the entities with every field optional; `WorkshopMapper` fills defaults field by field
  and skips records without the ids everything else hangs off. Costs are stored as decimal strings.
* `FileWorkshopRepository` writes `workshop.json` atomically with file protection; a newer `schemaVersion`
  opens read-only and leaves the file alone; an unreadable file is moved aside, never overwritten.
* `FilePhotoStore` keeps each photo as its own JPEG referenced by name.
* `NotificationReminderScheduler` rebuilds owner-only due reminders after each change.

## Presentation

* `DesignSystem/` — tokens (`CK.Palette`, `CK.Space`, `CK.Radius`), a Dynamic-Type type scale (`CKFont`,
  small-caps `CKLabel`, scaled `ckFigure`), buttons, cards, fields, steppers, status badges and the `UnitRack`
  instrument. Status is always words + icon, never colour alone.
* `Navigation/` — `AppRouter` (section, Home overlay, one programmatic push per section), the custom section
  bar over a system `TabView`, and `RouteLink` for pushes on iOS 15 without `NavigationStack`.
* Screens read `WorkshopStore.workshop` / `balances` and call use cases; forms keep drafts locally and show a
  refusal as a sentence at the top.
