# Invoices and Credit Notes Plan

## Goal

Add supplier-side invoice tracking to the existing event-sourced movement model:

- `Factura`: a supplier invoice, representing an amount due to flow out at a due date.
- `Nota de crédito`: a supplier credit note, representing an amount pending to flow in / offset at a due date.
- Cashflow movements (`Gasto`, `Ingreso`) can be marked as related to invoices with a boolean flag.
- Invoice-like movements should not appear in the current cashflow movements table. They should appear in a new invoice table that shows individual documents and summarizes the period's invoice obligations after subtracting invoice-related cashflows.
- Invoice-like movements get an optional user-entered document number (`Número`), stored as an arbitrary string for future matching/allocation work.

This plan intentionally stops at aggregate tracking. It does **not** introduce invoice IDs, allocation, partial settlement by invoice, supplier master data, status workflows, issue dates, or full double-entry accounting yet.

## Product decisions

Resolved decisions from the feature discussion:

1. `Fecha` means `due_date` for `Factura` / `Nota de crédito`.
   - We do not track user-input issue dates.
   - We care about `created_at`, but it is not user-inputable. For this pass, keep relying on event/document metadata for creation time rather than adding it to the form.
2. Reuse the existing `Cuenta` field.
   - The account is the account being invoiced, not the supplier/provider issuing the invoice.
   - No separate provider field in this pass.
3. The invoice table shows individual invoice/credit-note rows, plus totals.
4. Totals should include a final amount due after subtracting movements marked `relatedToInvoice`.
5. Display follows the app's current accounting notation:
   - Negative values: red, parenthesized absolute value, e.g. `(ARS 10.000,00)`.
   - Positive values: black, absolute value, e.g. `ARS 10.000,00`.
6. Related cashflow movements are not displayed as rows in the invoice table for now.
   - They are only used to compute the total `A pagar`.
   - Future direction: allocate payments automatically to invoices ordered by `due_date`, and show payment allocations as expandable sub-items.
7. Invoice table export is included in the first pass.
8. After saving a movement marked `Relacionado a factura`, reset the checkbox to `False`.
9. Invoice exchange-rate conversion is explicitly approximate when the invoice due date is in the future or when the invoice is not fully covered by related cashflow movements.
   - The exact source-of-truth amount is always the entered `inputAmount` + `inputCurrency`.
   - Converted `ars`/`usd` values for invoice-like movements are estimates based on the rate known at recording time.
   - This is acceptable for now, but the UI/export should avoid presenting those converted totals as final truth.

Assumption to keep implementation moving: the optional `Número` field applies to both `Factura` and `Nota de crédito`, since both are invoice-like documents. If it should be only for `Factura`, adjust before implementation.

## Architectural note: double-entry accounting later

Moving toward double-entry accounting eventually makes sense, especially for `Cuentas por pagar`, credit notes, allocations, and future accounts receivable/collectible concepts. It would make balances less ad-hoc and reduce ambiguity around invoices, payments, credits, and allocations.

For this feature, do **not** jump to double-entry yet:

- The existing app is event-sourced around movement events, and the requested behavior can be added with small additive schema changes.
- The business context allows payments unrelated to invoices, so forcing journal-style structure now may add friction.
- The boolean `relatedToInvoice` is explicitly transitional and should be treated as a stepping stone toward allocation by ID later.

Implementation should avoid storing derived balances. Store facts (`movementType`, `due_date` via `date`, `documentNumber`, `relatedToInvoice`) and compute totals in projections/views. That keeps the path open for a future projector that emits proper accounting ledgers.

## Current architecture touchpoints

- Domain model: `src/Accounting.elm`
  - `MovementType = ExpenseMovement | IncomeMovement`
  - `Movement` stores signed `ars`/`usd`, `date`, account snapshot, input amount/currency/rate, and `deletedAt`.
  - `Form` maps directly to a movement.
- Event log: `src/Events.elm`
  - `MovementCreatedEvent`, `MovementUpdatedEvent`, `MovementDeletedEvent`.
  - Events store full movement payloads.
- Projection: `src/Projector.elm`
  - Projects the event list into `List Movement`.
- Model/update: `src/Model.elm`, `src/Update/Movements.elm`, `src/Main.elm`
  - Model currently keeps all projected movements in `expenses`.
  - `Model.visibleMovements` filters by date/account and sorts before rendering/export.
- UI:
  - `src/View/MovementForm.elm` for entering movements.
  - `src/View/MovementTable.elm` for the current table, filters, sorting, export controls.
  - `src/View/App.elm` lays out form, admin panel, and table stack.
- Persistence/interop:
  - `public/app.js` appends events to local storage / Firestore and caches full ledgers.
  - Elm decoders need backwards-compatible defaults for newly-added event fields.
- Tests:
  - `tests/AccountingTest.elm`
  - `tests/ProjectorTest.elm`
  - `tests/UpdateTest.elm`

## Proposed domain model

### Movement types

Extend `Accounting.MovementType`:

```elm
type MovementType
    = ExpenseMovement
    | IncomeMovement
    | SupplierInvoiceMovement
    | SupplierCreditNoteMovement
```

String encoding:

- `ExpenseMovement` → `"Expense"` (existing)
- `IncomeMovement` → `"Income"` (existing)
- `SupplierInvoiceMovement` → `"SupplierInvoice"`
- `SupplierCreditNoteMovement` → `"SupplierCreditNote"`

Keep old event strings stable for compatibility.

### Movement fields

Add these fields to `Movement`:

```elm
relatedToInvoice : Bool
documentNumber : Maybe String
```

Rules:

- `relatedToInvoice`
  - Meaningful for `ExpenseMovement` and `IncomeMovement` only.
  - Defaults to `False` for old events, cached movements, and new empty forms.
  - Forced to `False` for `SupplierInvoiceMovement` and `SupplierCreditNoteMovement` in `buildMovement`.
- `documentNumber`
  - Meaningful for `SupplierInvoiceMovement` and `SupplierCreditNoteMovement` only.
  - Optional arbitrary string; trim whitespace and store `Nothing` when empty.
  - Defaults to `Nothing` for old events/caches.
  - Forced to `Nothing` for `ExpenseMovement` and `IncomeMovement`.

### Form fields

Add these fields to `Form`:

```elm
relatedToInvoice : Bool
documentNumber : String
```

`documentNumber` is a raw form string so the input remains simple. Normalize it in `buildMovement`.

### Date semantics

Keep the existing `date : String` field for a smaller migration, but treat it contextually:

- Cashflow movements: `date` means cash movement date, as today.
- Invoice-like movements: `date` means `due_date`.

UI labels should reflect this:

- For cashflow movement types: `Fecha`.
- For `Factura` / `Nota de crédito`: `Vencimiento` or `Fecha de vencimiento`.

Exports for the invoice table should label this column `Vencimiento`.

### Created-at semantics

Do not add a user-editable `created_at` field.

Current cloud writes already include `createdAt: serverTimestamp()` in event documents. For the first pass:

- Do not use `createdAt` in invoice calculations.
- Do not expose it in the form.
- If we need to show or sort by creation time later, add event metadata decoding and ensure local-mode events also receive a client timestamp.

### Exchange-rate uncertainty for future due dates

Cashflow movements normally describe something that already happened by the moment of recording, so using the known/current exchange rate is at least defensible. Invoice-like movements are different: they can be due in the future, so the true exchange rate at settlement is unknown.

First-pass behavior:

- Keep using the existing required `exchangeRate`, `ars`, and `usd` fields for invoice-like movements to avoid a larger schema split.
- Treat invoice-like movement conversions as **estimated** values, not final accounting truth.
- The exact source-of-truth amount remains `inputAmount` in `inputCurrency`.
  - If an invoice is entered in USD, the USD amount is exact and the ARS conversion is estimated.
  - If an invoice is entered in ARS, the ARS amount is exact and the USD conversion is estimated.
- The stored invoice `exchangeRate` should be understood as “rate used for estimate at recording time”, even if the field name remains `exchangeRate` for compatibility.
- `A pagar` in a single display currency is an estimate whenever it includes invoice-like movements whose original currency differs from the selected display currency, or future/open invoices whose true settlement rate is unknown.
- Cashflow movements marked `relatedToInvoice` are treated as actual cashflow values using their movement exchange rate. For now they are subtracted in aggregate; exactness improves only once payments can be allocated to specific invoices.

Near-term UI/export requirements:

- In invoice rows, keep showing `Ingresado` as the exact original amount/currency.
- Label converted invoice columns as estimated, e.g. `Cotización estimada` and `Total estimado`, or add a short note in the invoice table: `Los totales convertidos de facturas son estimaciones hasta que se cubren con movimientos relacionados.`
- Prefer displaying exact per-currency subtotals for invoice documents if it remains simple:
  - `Facturas ARS`, `Facturas USD`
  - `Notas de crédito ARS`, `Notas de crédito USD`
  - The existing selected-currency totals can remain as the operational estimate.
- Export should carry the same estimate labeling/notes so CSV/XLSX users do not mistake converted invoice totals for finalized values.

Future strategies, in increasing complexity:

1. **Exchange-rate history for due dates**
   - Store/fetch daily exchange rates.
   - For invoices whose `due_date` is now in the past, recompute estimates using the historical due-date rate.
   - Future due dates remain estimates until their due date arrives.

2. **Manual rate override / revaluation**
   - Add a way to edit the estimated/final rate for an invoice-like movement.
   - Event-sourced shape could be a new `InvoiceExchangeRateUpdatedEvent` or reuse `MovementUpdatedEvent` while preserving the original amount/currency.
   - Useful when the business has a negotiated rate or wants to revalue open invoices periodically.

3. **Allocation-based realization**
   - Replace the boolean `relatedToInvoice` with allocations from cashflow movements to one or more invoice IDs.
   - Once an invoice is fully allocated, compute its realized value from the actual covering cashflows instead of its estimated conversion.
   - Partial allocations can show remaining estimated balance plus realized paid amount.

4. **Double-entry accounting**
   - Represent invoices as `Cuentas por pagar` entries, payments as reductions of payables, and exchange differences as FX gain/loss adjustments.
   - This is the clean long-term model, but it is intentionally out of scope for the first pass.

### Sign conventions

Preserve the existing signed `ars`/`usd` convention:

| Type | Meaning | Signed value |
| --- | --- | --- |
| `Gasto` | Cash outflow | negative |
| `Ingreso` | Cash inflow | positive |
| `Factura` | Supplier amount due / future outflow | negative |
| `Nota de crédito` | Supplier credit / future inflow or offset | positive |

This allows period netting with the existing `MoneyTotal` shape.

Display should reuse the existing formatter convention from `Util.Format`:

- `formatMoney`/`formatNumber` render negative values as parenthesized absolutes.
- Table cells with negative totals should get `is-negative` so they render red.

## Derived movement groups

Add helpers in `Accounting.elm` (names can be adjusted during implementation):

```elm
isCashflowMovement : Movement -> Bool
isCashflowMovement movement =
    movement.movementType == ExpenseMovement || movement.movementType == IncomeMovement

isInvoiceMovement : Movement -> Bool
isInvoiceMovement movement =
    movement.movementType == SupplierInvoiceMovement || movement.movementType == SupplierCreditNoteMovement

isInvoiceRelatedCashflow : Movement -> Bool
isInvoiceRelatedCashflow movement =
    isCashflowMovement movement && movement.relatedToInvoice
```

Model-level derived lists:

- `Model.visibleCashflowMovements`
  - Active, date-filtered, account-filtered, sorted cashflow rows only.
  - Replaces current `Model.visibleMovements` usage in the cashflow table/export.
- `Model.visibleInvoiceMovements`
  - Active, date-filtered, account-filtered, sorted invoice/credit-note rows only.
  - Uses `date` as `due_date` for filtering.
- `Model.visibleInvoiceRelatedCashflows`
  - Active, date-filtered, account-filtered cashflow rows where `relatedToInvoice = True`.
  - Used only by invoice table summary/export, not displayed as invoice table rows.

Keep `expenses` as the model field name for the first implementation if we want a smaller diff. Optionally rename it to `movements` in a separate cleanup after the feature is stable.

## Event and decoder changes

### Event payload

Add `relatedToInvoice` and `documentNumber` to created/updated movement data:

```elm
movement_created.data.movement.relatedToInvoice : Bool
movement_created.data.movement.documentNumber : Maybe String

movement_updated.data.relatedToInvoice : Bool
movement_updated.data.documentNumber : Maybe String
```

Update:

- `Events.MovementCreatedData`
- `Events.MovementUpdatedData`
- `Events.dataEncoder`
- `Events.movementDataDecoder`
- `Events.movementUpdatedDecoder`
- `Projector.movementCreated`
- `Projector.applyUpdate`
- `Update.Movements.persistMovement`

### Backwards compatibility

Required compatibility behavior:

- Existing events without `relatedToInvoice` decode as `False`.
- Existing events without `documentNumber` decode as `Nothing`.
- Existing cached projected movements without either field decode with defaults in `Ledger.movementDecoder`.
- Existing `movementType` strings keep decoding exactly as today.
- Unknown `movementType` currently falls back to `ExpenseMovement`; keep that fallback unless we decide to surface decode errors.

Implementation note: use optional/default decoding rather than requiring the new fields.

### Event version

The app already writes `version = 1`. Recommendation: keep `version = 1` because the decoder remains backwards-compatible and the schema change is additive. If we later branch decoder behavior by version, bump then.

## Form and update flow

### Form behavior

Update `src/View/MovementForm.elm`:

- Add radio options:
  - `Gasto`
  - `Ingreso`
  - `Factura`
  - `Nota de crédito`
- Add `Número` input only for invoice-like movement types:
  - Render above `Descripción`.
  - Optional.
  - Plain text input, not numeric, because document numbers may contain arbitrary characters.
- Add a checkbox for cashflow movements only:
  - Label: `Relacionado a factura`
  - Helper text suggestion: `Se usa para calcular el total a pagar de facturas y notas de crédito.`
- Change the date label based on movement type:
  - Cashflow: `Fecha`
  - Invoice-like: `Vencimiento`
- Button labels:
  - `Registrar gasto`
  - `Registrar ingreso`
  - `Registrar factura`
  - `Registrar nota de crédito`

Update `src/Accounting.elm`:

- Add `setRelatedToInvoice : Bool -> Form -> Form`.
- Add `setDocumentNumber : String -> Form -> Form`.
- Update `emptyForm`, `movementToForm`, and `buildMovement`.
- `buildMovement` should normalize:
  - `relatedToInvoice = False` for invoice-like movement types.
  - `documentNumber = Nothing` for cashflow movement types.

Update `src/Main.elm` and `src/Config.elm`:

- Add message callbacks for `relatedToInvoice` and `documentNumber`.
- Wire through `Config.Messages`, `View.App`, and `View.MovementForm`.

Update `src/Update/Movements.elm`:

- Include `relatedToInvoice` and `documentNumber` in create/update events.
- When resetting the form after save, preserve date/currency/account as today.
- Reset `relatedToInvoice = False` after every save.
- Reset `documentNumber = ""` after every save.

## Cashflow table changes

Update `src/View/MovementTable.elm` behavior:

- Rename the section from `Gastos` to something that matches mixed cashflow, e.g. `Movimientos de caja`.
- Render only `ExpenseMovement` and `IncomeMovement` rows.
- Add a small indicator for `relatedToInvoice` on cashflow rows.
  - Preferred minimal option: append a badge in the description cell: `Factura`.
  - Avoid adding a full column unless the UI still has enough room.
- Keep existing filters, account toggles, date display, currency display, sorting, and cashflow export controls.

Potential naming cleanup:

- Internally many functions/classes say `expense`. Avoid a large rename during the first pass unless it blocks clarity.
- UI text should stop saying `gastos` when the table contains both incomes and expenses.

## New invoice table

Create `src/View/InvoiceTable.elm`.

Inputs:

```elm
type alias Config msg =
    { invoices : List Movement
    , relatedCashflows : List Movement
    , dateDisplay : DateDisplay
    , displayCurrency : Currency
    , sortField : SortField
    , sortDirection : SortDirection
    , onSelectSort : SortField -> msg
    , onExportCsv : msg
    , onExportXlsx : msg
    , onDelete : String -> msg
    , onEdit : String -> msg
    }
```

Rows:

- Show individual `Factura` and `Nota de crédito` movements only.
- Do **not** show `relatedToInvoice` cashflow movements as rows.
- Columns:
  - Vencimiento
  - Tipo
  - Cuenta
  - Número
  - Descripción
  - Ingresado
  - Cotización estimada
  - Total estimado
  - Acciones

Sorting:

- Reuse current sort state where possible (`date`, `account`, `description`, exchange rate, totals).
- `Número` can be non-sortable initially.
- If sorting by type/number is cheap and does not complicate shared sort state too much, add `SortByMovementType` and/or `SortByDocumentNumber`; otherwise defer.

Summary rows:

- `Total facturas`
- `Total notas de crédito`
- `Total documentos` / `Total documentos estimado` when displayed in a converted currency
- `Movimientos relacionados`
- `A pagar` / `A pagar estimado` when the selected-currency total is not fully realized

Signed formula:

```text
totalDocumentos = totalFacturas + totalNotasDeCredito
movimientosRelacionados = sum(relatedToInvoice cashflow movements)
aPagar = totalDocumentos - movimientosRelacionados
```

Examples:

```text
Factura 100                      -> totalDocumentos = -100
Pago relacionado 40              -> movimientosRelacionados = -40
A pagar = -100 - (-40) = -60     -> displayed red as (60)

Factura 100 + nota de crédito 20 -> totalDocumentos = -80
Pago relacionado 40              -> movimientosRelacionados = -40
A pagar = -80 - (-40) = -40      -> displayed red as (40)
```

If there are related `Ingreso` movements, include them in `movimientosRelacionados` using the same signed formula for now. This may be confusing in edge cases, but it matches the agreed transitional behavior and avoids introducing allocation/refund rows prematurely.

Estimate labeling:

- The invoice table must make clear that converted invoice totals are estimates.
- The exact row value is `Ingresado` in the original currency.
- The selected-currency summary is operationally useful, but not final accounting truth until invoices are covered by allocated related movements in a future implementation.

Placement:

- Add `InvoiceTable.view` below the cashflow table in `src/View/App.elm` inside `.content-stack`.
- Use the same period/account/date/currency state as the cashflow table so both tables stay aligned.
- If there are no invoice-like movements and no invoice-related cashflows in the selected period, show an empty state such as `Todavía no hay facturas ni notas de crédito para este período.`

## Export

Include invoice export in this first pass.

Cashflow export:

- Keep the existing export controls on the cashflow table.
- Rename generated labels/filenames if the table is no longer only `Gastos`.

Invoice export:

- Add `Export.invoiceTablePayload` with sheet name `Facturas`.
- Add separate `Exportar CSV/XLSX` controls to `InvoiceTable` to avoid ambiguity.
- Export a simple flat table:
  - Same columns as invoice table, excluding `Acciones`.
  - Use estimate-aware headers such as `Cotización estimada` and `Total estimado`.
  - Include summary rows after invoice rows.
  - Do not export individual `relatedToInvoice` cashflow rows; only include their aggregate summary.
  - Include a note row or metadata-style row explaining that converted invoice totals are estimates until covered by related movements/allocation.

Required wiring:

- Add `ExportInvoicesCsv` and `ExportInvoicesXlsx` messages in `Main.elm`.
- Add callbacks through `Config.Messages` / `View.App` / `View.InvoiceTable`.
- Reuse the existing `exportTable` port and JS download logic.

## Styling

Update `public/index.css`:

- Reuse existing table styles for the invoice table.
- Prefer extracting generic table classes over duplicating all `.expense-table` rules:
  - e.g. keep `.expense-table` for compatibility and add `.ledger-table` shared styles.
- Add lightweight badge styles for cashflow rows related to invoices.
- Ensure mobile card layout works for new labels:
  - `Vencimiento`
  - `Tipo`
  - `Número`
- Ensure invoice summary rows apply `is-negative` for red negative totals.

## Tests

Add/update tests:

### `tests/AccountingTest.elm`

- `cashflowFor`/sign helper returns negative for `SupplierInvoiceMovement`.
- Sign helper returns positive for `SupplierCreditNoteMovement`.
- `buildMovement` includes `relatedToInvoice = True` for income/expense when selected.
- `buildMovement` forces `relatedToInvoice = False` for invoices/credit notes.
- `buildMovement` stores trimmed `documentNumber` for invoices/credit notes.
- `buildMovement` forces `documentNumber = Nothing` for income/expense.
- New movement type string round trips.

### `tests/ProjectorTest.elm`

- Projection preserves `relatedToInvoice` and `documentNumber` on created and updated events.
- Projection handles `SupplierInvoiceMovement` and `SupplierCreditNoteMovement`.

### `tests/UpdateTest.elm` or new movement update tests

- Creating/updating a movement writes `relatedToInvoice` into the event payload.
- Creating/updating an invoice-like movement writes `documentNumber` into the event payload.
- Form reset clears `relatedToInvoice` and `documentNumber` after save.

### Decoder compatibility tests

Add tests for old event JSON:

- Old `movement_created` without `relatedToInvoice` decodes as `False`.
- Old `movement_created` without `documentNumber` decodes as `Nothing`.
- Old cached movement without either field decodes with defaults.

### Invoice summary tests

Add pure tests for whatever helper computes invoice totals:

- Invoice only → `A pagar` equals invoice total.
- Invoice + related expense payment → `A pagar` subtracts the payment.
- Invoice + credit note + related expense payment → `A pagar` nets all signed values.
- Mixed-currency invoice summaries preserve exact `inputAmount`/`inputCurrency` row values while selected-currency totals are treated as estimates.

## Implementation steps

1. [ ] Update domain model in `src/Accounting.elm`:
   - Extend `MovementType`.
   - Add `relatedToInvoice` and `documentNumber` to `Movement` and `Form`.
   - Add predicates for cashflow vs invoice-like movements.
   - Add invoice-related filtering helpers.
   - Update sign conversion and string conversion.
   - Add invoice summary helper if keeping summary math outside the view.

2. [ ] Update event schema in `src/Events.elm`:
   - Add `relatedToInvoice` and `documentNumber` fields.
   - Encode/decode with backwards-compatible defaults.

3. [ ] Update projection in `src/Projector.elm`:
   - Carry `relatedToInvoice` and `documentNumber` through creates and updates.

4. [ ] Update ledger decoders in `src/Ledger.elm`:
   - Decode cached/projected movements with default `relatedToInvoice = False` and `documentNumber = Nothing`.

5. [ ] Update create/update/delete flow in `src/Update/Movements.elm` and `src/Main.elm`:
   - Wire new form messages.
   - Include new fields in events.
   - Reset form safely after save.

6. [ ] Update app configuration in `src/Config.elm` and `src/View/App.elm`:
   - Pass new form callbacks.
   - Use cashflow-only rows for the existing table.
   - Add invoice table below it.
   - Pass invoice export callbacks.

7. [ ] Update `src/View/MovementForm.elm`:
   - Add `Factura` / `Nota de crédito` options.
   - Add `Número` input above description for invoice-like movements.
   - Add `Relacionado a factura` checkbox for cashflow types.
   - Update date label and button labels.

8. [ ] Update `src/View/MovementTable.elm`:
   - Rename UI text to cashflow language.
   - Add related-to-invoice badge.

9. [ ] Add `src/View/InvoiceTable.elm`:
   - Display invoice-like rows.
   - Display invoice/payment summary for the selected period.
   - Reuse sorting/actions/date/currency formatting.
   - Add estimate-aware labels/notes for converted invoice values.
   - Add invoice export controls.

10. [ ] Update `src/Export.elm`:
    - Rename/adjust cashflow export text if needed.
    - Add `invoiceTablePayload`.
    - Use estimate-aware invoice headers/notes.

11. [ ] Update `public/index.css`:
    - Shared table styles / invoice table styles.
    - Badge styles.
    - Mobile responsive labels.

12. [ ] Add/update tests.

13. [ ] Validate:
    - `nix run .#format -- --validate`
    - `nix run .#test`
    - `nix run .#review`
    - `nix run .#build`

## No remaining blockers

The plan is ready to implement with one accepted caveat: invoice converted totals are estimates until exchange rates are known and/or invoices are covered by allocated related movements. The only non-blocking assumption is that `Número` applies to both `Factura` and `Nota de crédito`.
