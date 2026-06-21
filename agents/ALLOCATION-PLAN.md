# Invoice Allocation Plan

## Goal

Evolve invoice-related cashflow tracking from a boolean marker into deterministic, event-sourced allocation between:

- `ExpenseMovement` cashflows and supplier invoices.
- `IncomeMovement` cashflows and supplier credit notes.
- Supplier credit notes and supplier invoices, because credit notes can offset invoices directly.

The output of this feature is a derived allocation/status model that can answer, ledger-wide:

- Which invoices are pending, partially paid, fully paid, or overpaid.
- Which credit notes are pending, partially collected/applied, fully collected/applied, or over-collected/over-applied.
- How much remains due per document in that document's nominal currency.
- Which allocations were explicitly selected by the user vs automatically selected by the app.

This is a high-risk feature because allocation semantics become part of the event-sourced history. Store user/system intent immutably; compute allocation amounts and statuses deterministically in pure projection code.

## Core decisions

1. Allocation strategy should be an Elm union type, not an arbitrary `Maybe String`.
   - Strategies are known ahead of time.
   - JSON events still serialize union values as stable strings, but Elm should decode them into explicit variants.
2. Expense cashflows can only allocate to invoices.
3. Income cashflows can only allocate to credit notes.
4. Credit notes must be associated with invoices and offset those invoices directly.
   - New credit notes require at least one target invoice.
   - Target invoices must have the same `accountId` and the same `inputCurrency` as the credit note.
   - A credit note effectively changes the amount due on its associated invoice(s), and nothing more.
5. Allocation candidates must have the same `accountId` as the source movement.
6. Cross-currency allocation is supported for cashflow-to-document allocations.
   - Compute allocated amounts in the target document's nominal currency.
   - Use the cashflow movement's exchange rate at registration time for cashflow allocations.
   - If exchange rates are edited later, recompute the cashflow's opposite-currency value and derived allocations/statuses.
   - Document-to-document credit-note offsets are same-currency only; document exchange rates are only UX/display clues.
7. If no documents are manually selected for a cashflow, resolve target document IDs at save time.
   - Store that the app selected them automatically for auditability.
   - Do not let future invoices/credit notes retroactively “steal” an old payment/refund.
8. Allocation order for related cashflows is movement date ascending, then ID/created-at.
   - Today, use `date`, then movement `id` as the deterministic tie-breaker.
   - If event `createdAt` is decoded later, use `date`, then `createdAt`, then `id`.
9. Document status is ledger-wide/current-known state, not period-local.
10. Invoice report period semantics:
    - The invoice table filters invoice/credit-note documents by their `due_date` (`Movement.date`).
    - Status and remaining due for displayed documents use ledger-wide allocations.
    - Cashflows related to invoices due outside the selected period do **not** affect that period's invoice totals, because their target documents are not in the period.
    - Those cashflows still appear in cashflow reports based on their own cashflow date.
11. Exact-match auto-selection uses exact remaining due after previous allocations, converted using the cashflow rate.
12. Exact-match tolerance is `1 USD` or the equivalent in ARS using the real exchange rate available on the movement.
13. When a cashflow is related to invoices/credit notes, the picker replaces the free description input.
    - Generated description for expenses: `Pago factura ${document_number}` or `Pago facturas ${numbers}`.
    - Generated fallback when invoice numbers are missing: `Pago facturas`.
    - Generated description for incomes: `Cobro nota de crédito ${document_number}` or `Cobro notas de crédito ${numbers}`.
    - Generated fallback when credit-note numbers are missing: `Cobro notas`.
14. Do not block saving when selected documents cannot exactly absorb the cashflow amount.
    - Show clear Spanish feedback before save.
    - Overpayment is allowed and applied to the oldest selected document.

## Relationship types

There are three allocation relationship types:

```elm
type AllocationKind
    = ExpenseToInvoice
    | IncomeToCreditNote
    | CreditNoteToInvoice
```

Derived from source movement type:

| Source movement type | Target movement type | Allocation kind |
| --- | --- | --- |
| `ExpenseMovement` | `SupplierInvoiceMovement` | `ExpenseToInvoice` |
| `IncomeMovement` | `SupplierCreditNoteMovement` | `IncomeToCreditNote` |
| `SupplierCreditNoteMovement` | `SupplierInvoiceMovement` | `CreditNoteToInvoice` |
| `SupplierInvoiceMovement` | none | none |

Validation/candidate rules:

- Source and target must share the same `accountId`.
- Deleted source or target movements are ignored by the allocation projector.
- An expense cannot target a credit note.
- An income cannot target an invoice.
- A credit note can target invoices only.
- A credit note can target only invoices with the same `inputCurrency`.

## Types

### Strategy as union types

Use explicit union types internally:

```elm
type AllocationStrategy
    = OldestDueFirstThenOverpayOldest


type TargetSelectionSource
    = UserSelectedTargets
    | AutoSelectedTargets AutoSelectionReason
    | MigrationSelectedTargets MigrationSelectionReason
    | LegacyDynamicTargets


type AutoSelectionReason
    = AutoExactRemainingDueMatch
    | AutoAllOpenDocuments
    | AutoNoCandidates


type MigrationSelectionReason
    = MigrationImportedExplicitTargets
    | MigrationInferredFromDocumentNumber
    | MigrationInferredFromExactAmount
    | MigrationInferredFromLegacyBoolean
```

Notes:

- `AllocationStrategy` has one v1 variant, but making it a union now prevents stringly-typed branching later.
- `TargetSelectionSource` satisfies the auditability requirement: we can tell whether a user selected documents, the app filled them in automatically, or a migration inferred them.
- `LegacyDynamicTargets` is only for compatibility/backfill edge cases. New app-created movements should store resolved target IDs.

### Allocation intent stored on movements

Add an optional allocation intent to movements that can allocate to documents:

```elm
type alias AllocationIntent =
    { targetIds : List String
    , targetSelectionSource : TargetSelectionSource
    , strategy : AllocationStrategy
    }
```

Movement field:

```elm
allocationIntent : Maybe AllocationIntent
```

Rules:

- `ExpenseMovement`: `allocationIntent = Just ...` means this expense is related to invoices.
- `IncomeMovement`: `allocationIntent = Just ...` means this income is related to credit notes.
- `SupplierCreditNoteMovement`: `allocationIntent = Just ...` means this credit note offsets invoice(s).
- `SupplierInvoiceMovement`: `allocationIntent = Nothing`.

Compatibility with the invoice MVP:

- If `relatedToInvoice : Bool` already exists, keep it as a legacy/UX shorthand on cashflows.
- The allocation source of truth becomes `allocationIntent`.
- For old events with `relatedToInvoice = True` and no `allocationIntent`, decode/project as a legacy related cashflow and handle through migration or `LegacyDynamicTargets` only when explicitly needed.

### Serialized event shape

JSON should store stable strings/lists, decoded into the union types above:

```json
{
  "allocationIntent": {
    "targetIds": ["movement-id-1", "movement-id-2"],
    "targetSelectionSource": "user_selected",
    "autoSelectionReason": null,
    "migrationSelectionReason": null,
    "strategy": "oldest_due_first_then_overpay_oldest"
  }
}
```

Suggested strings:

- `strategy`
  - `oldest_due_first_then_overpay_oldest`
- `targetSelectionSource`
  - `user_selected`
  - `auto_selected`
  - `migration_selected`
  - `legacy_dynamic`
- `autoSelectionReason`
  - `exact_remaining_due_match`
  - `all_open_documents`
  - `no_candidates`
- `migrationSelectionReason`
  - `imported_explicit_targets`
  - `inferred_from_document_number`
  - `inferred_from_exact_amount`
  - `inferred_from_legacy_boolean`

Backwards compatibility:

- Missing `allocationIntent` decodes as `Nothing`.
- Missing/unknown strategy on old imported data should decode to `OldestDueFirstThenOverpayOldest` only if there are explicit target IDs; otherwise leave as `Nothing` and surface a migration warning.

## Derived allocation records

Do not store allocation amounts as event facts for normal app flows. Compute them from projected movements and `AllocationIntent`.

Pure projection output:

```elm
type alias Allocation =
    { kind : AllocationKind
    , sourceMovementId : String
    , targetMovementId : String
    , amountInSourceCurrency : Float
    , sourceCurrency : Currency
    , amountInTargetCurrency : Float
    , targetCurrency : Currency
    , targetSelectionSource : TargetSelectionSource
    , strategy : AllocationStrategy
    }
```

Why compute amounts instead of storing them:

- Editing invoice/cashflow amounts or exchange rates should recompute statuses deterministically.
- Migration/import can preserve intent separately from derived results.
- Avoids event histories where stored allocation amounts contradict current movement facts.

Exception for migrations:

- If a legacy schema contains explicit allocation amounts that cannot be faithfully represented by target IDs + strategy, import those into a separate migration-only field or create a dedicated `ManualAllocationOverride` design. Do not silently mix override amounts with heuristic-derived amounts.

## Currency conversion

### Cashflow to document allocation

Use the cashflow movement's exchange rate to compute the amount allocated in the target document currency. This applies to `ExpenseToInvoice` and `IncomeToCreditNote` allocations.

Examples:

```text
Invoice: USD 100
Payment: ARS 148,500 with exchangeRate 1485
Allocated to invoice: USD 100
Invoice status: Fully paid
```

```text
Credit note: USD 100
Refund income: ARS 74,250 with exchangeRate 1485
Allocated to credit note: USD 50
Credit note status: Partially collected/applied, unless the remaining USD 50 is also offset to invoices
```

Rules:

- The source cashflow amount is exact in `sourceCurrency`.
- The target document status is computed in `targetCurrency`.
- Use the same conversion logic as `Accounting.convert`, but anchored on the cashflow's `exchangeRate`.
- Never use display currency as an accounting basis.

### Credit-note to invoice offsets

Credit-note-to-invoice offsets are same-currency only:

- A credit note can only be associated to invoices with the same `inputCurrency`.
- No exchange rate is needed to apply the credit note to an invoice.
- The credit note's stored exchange rate may still be useful for showing the due/offset amount in the other currency as a UX clue, but it is not part of allocation math.
- If an invoice has a different currency, it is not an eligible target for the credit note picker or allocation projector.

### Tolerance

Use tolerance in the target document currency:

```elm
toleranceFor : Currency -> Float -> Float
toleranceFor targetCurrency exchangeRate =
    case targetCurrency of
        USD ->
            1

        ARS ->
            exchangeRate
```

Use the source cashflow exchange rate for exact-match comparisons involving cashflows. Credit-note-to-invoice offsets do not need tolerance-based currency conversion because their targets must share the same currency.

## Allocation algorithms

### Common helpers

For each allocation source:

1. Resolve target IDs.
2. Validate/filter targets:
   - active only;
   - same account only;
   - correct target type only.
3. Sort selected targets by:
   - `due_date` / `date` ascending;
   - then `createdAt` when available;
   - then movement `id`.
4. Allocate source amount with `OldestDueFirstThenOverpayOldest`.

### Target resolution at save time

When the user selects target documents manually:

```elm
{ targetIds = selectedIds
, targetSelectionSource = UserSelectedTargets
, strategy = OldestDueFirstThenOverpayOldest
}
```

When the user marks a cashflow as related but selects no documents:

1. Compute eligible documents at save time:
   - same account;
   - active;
   - correct type;
   - not fully settled before the new cashflow is applied.
2. Try exact remaining-due match:
   - Convert the cashflow amount into each eligible document's nominal currency using the cashflow exchange rate.
   - Compare against each document's current remaining due after previous allocations.
   - Use tolerance: `1 USD` or equivalent ARS.
   - If multiple match, choose oldest due date, then ID.
3. If exact match found:

```elm
{ targetIds = [ matchedDocumentId ]
, targetSelectionSource = AutoSelectedTargets AutoExactRemainingDueMatch
, strategy = OldestDueFirstThenOverpayOldest
}
```

4. If no exact match:

```elm
{ targetIds = allEligibleOpenDocumentIds
, targetSelectionSource = AutoSelectedTargets AutoAllOpenDocuments
, strategy = OldestDueFirstThenOverpayOldest
}
```

5. If no candidates exist, allow saving with a warning and store:

```elm
{ targetIds = []
, targetSelectionSource = AutoSelectedTargets AutoNoCandidates
, strategy = OldestDueFirstThenOverpayOldest
}
```

and show a warning that this cashflow is marked for document allocation, but there are no eligible documents in the selected account.

### Allocation fold

For a source amount and selected targets:

```text
remainingSourceAmount = abs(source.inputAmount)
selectedTargets = sorted by due_date, id

for each not-fully-settled selected target:
  allocate min(remainingSourceAmount converted to target currency, target.remainingDue)
  reduce remainingSourceAmount
  stop if remainingSourceAmount is zero within tolerance

if remainingSourceAmount remains after all selected targets are fully settled:
  allocate remainder to the oldest selected target
  that target becomes Overpaid / over-collected / over-applied
```

Important:

- Overpayment applies only to the oldest selected target.
- Do not allocate overpayment to arbitrary unselected documents.
- If selected targets are empty, no allocation can be produced; surface a warning.

### Processing order

Process allocation sources ledger-wide in deterministic order:

1. Credit-note refund incomes to credit notes.
2. Credit-note offsets to invoices, using credit remaining after refunds.
3. Expense payments to invoices.

Within each group:

- source movement `date` ascending;
- then `createdAt` if available;
- then movement `id`.

Reasoning:

- Income refunds reduce the effective credit note amount available to offset invoices.
- Credit notes reduce invoice payable before or alongside expenses.
- Expense payments then settle the remaining invoice due.

This ordering should be revisited with real examples, but it handles the core example:

```text
Invoice 1000
Expense payment 1000
Credit note 200 associated to invoice
No refund income

=> effective credit offset = 200
=> invoice due = 1000 - 200 - 1000 = -200
=> invoice Overpaid by 200
```

```text
Same as above, plus refund income 200 allocated to credit note

=> credit note remaining after refund = 0
=> effective credit offset = 0
=> invoice due = 1000 - 0 - 1000 = 0
=> invoice Fully paid
```

## Credit notes

Credit notes have two roles:

1. They can offset invoices directly.
2. They can be settled by income/refund cashflows.

For a credit note:

```text
creditNominal = abs(creditNote.inputAmount) in creditNote.inputCurrency
refundsCollected = income allocations to this credit note in creditNote.inputCurrency
creditAvailableToOffsetInvoices = max(0, creditNominal - refundsCollected)
```

Then allocate `creditAvailableToOffsetInvoices` to the invoices selected by the credit note's `allocationIntent`.

Credit-note invoice targets are mandatory for new credit notes and must be same-account/same-currency invoices. If a legacy import contains an unapplied credit note, migration should either ask for a target invoice or mark it unresolved rather than silently treating it as a free-floating supplier credit.

Credit note status:

```text
creditUsed = refundsCollected + effectiveInvoiceOffsets
remainingCredit = creditNominal - creditUsed
```

- `Pending`: no refunds and no invoice offsets.
- `Partially collected/applied`: `remainingCredit > tolerance` and some credit used.
- `Fully collected/applied`: `remainingCredit` is within tolerance.
- `Over-collected/over-applied`: `remainingCredit < -tolerance`.

Spanish labels depend on whether the credit note has refund income movements:

If the credit note has no income/refund movements and is only offsetting invoices:

- `Pendiente`
- `Parcialmente aplicada`
- `Aplicada`
- `Aplicada en exceso`

If the credit note has one or more income/refund movements:

- `Pendiente`
- `Parcialmente reembolsada`
- `Reembolsada`
- `Reembolsada en exceso`

If both refund movements and invoice offsets exist, prefer the `Reembolsada` family because actual cash was registered, while still showing the underlying applied/refunded breakdown in details when available.

## Invoice status

For an invoice:

```text
invoiceNominal = abs(invoice.inputAmount) in invoice.inputCurrency
creditOffsets = effective credit-note offsets to this invoice in invoice.inputCurrency
expensePayments = expense allocations to this invoice in invoice.inputCurrency
remainingDue = invoiceNominal - creditOffsets - expensePayments
```

Status:

- `Pending`: no credit offsets and no expense payments.
- `Partially paid`: `remainingDue > tolerance` and some credit/payment exists.
- `Fully paid`: `remainingDue` is within tolerance.
- `Overpaid`: `remainingDue < -tolerance`.

Spanish labels:

- `Pendiente`
- `Parcialmente pagada`
- `Pagada`
- `Sobrepagada`

## Period/report semantics

This is intentionally **document-period reporting**, not cashflow-period allocation reporting.

For selected period `P`:

- Invoice table includes invoice/credit-note documents whose `due_date` falls in `P`.
- Each displayed document's status is computed ledger-wide using all known allocations, regardless of cashflow date.
- Summary totals for `P` aggregate only displayed documents.
- Cashflows dated in `P` but allocated to documents due outside `P` do not affect invoice-table totals for `P`.
- Those cashflows still appear in the cashflow table/report for `P`.

Example:

```text
Invoice due in May.
Payment made in June.

May invoice report: shows the May invoice, status may be Pagada because status is ledger-wide.
June invoice report: does not include the May invoice/payment in invoice totals.
June cashflow report: includes the June payment.
```

Future possible report mode:

- Add an “as of date” toggle if users need historical status as of period end.
- That is out of scope for the first allocation implementation.

## UX behavior

### Cashflow form

When movement type is `Gasto` and the user marks it as invoice-related:

- Replace description input with invoice picker.
- Picker shows eligible same-account invoices.
- Generated description:
  - one target: `Pago factura ${documentNumber}`
  - multiple targets: `Pago facturas ${numbers}`
  - fallback when numbers are missing: `Pago facturas`

When movement type is `Ingreso` and the user marks it as invoice-related:

- Replace description input with credit-note picker.
- Picker shows eligible same-account credit notes.
- Generated description:
  - one target: `Cobro nota de crédito ${documentNumber}`
  - multiple targets: `Cobro notas de crédito ${numbers}`
  - fallback when numbers are missing: `Cobro notas`

Picker rows should show:

- Document number.
- Due date.
- Original amount/currency.
- Current remaining due in original currency.
- Status.

### Credit note form

When movement type is `Nota de crédito`:

- Show invoice picker for same-account and same-currency invoices.
- Require at least one invoice target for new credit notes.
- Store `allocationIntent` with `CreditNoteToInvoice` semantics.
- If there are no eligible invoices for that account/currency, block credit-note creation with a clear message asking the user to create/import the invoice first.

### Pre-save feedback

Do not block over/under allocation. Show understandable Spanish warnings.

For expenses/invoices:

- Cashflow exceeds selected remaining due:
  - `Estás pagando más de lo pendiente en las facturas seleccionadas. El sobrante quedará como sobrepago en la factura más antigua seleccionada.`
- Selected remaining due exceeds cashflow:
  - `El pago no alcanza para cubrir todas las facturas seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente.`
- No eligible documents found:
  - `Este pago está marcado para aplicarse a facturas, pero no hay facturas elegibles en esta cuenta. Puedes guardarlo, pero no quedará aplicado a ninguna factura.`

For incomes/credit notes:

- Cashflow exceeds selected remaining due:
  - `Estás cobrando más de lo pendiente en las notas de crédito seleccionadas. El sobrante quedará como cobro en exceso en la nota de crédito más antigua seleccionada.`
- Selected remaining due exceeds cashflow:
  - `El cobro no alcanza para cubrir todas las notas de crédito seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente.`
- No eligible documents found:
  - `Este cobro está marcado para aplicarse a notas de crédito, pero no hay notas de crédito elegibles en esta cuenta. Puedes guardarlo, pero no quedará aplicado a ninguna nota de crédito.`

For credit-note-to-invoice offsets:

- Credit note exceeds selected invoice due:
  - `La nota de crédito supera lo pendiente en las facturas seleccionadas. El sobrante quedará como crédito en exceso en la factura más antigua seleccionada.`
- Selected invoice due exceeds credit note:
  - `La nota de crédito no alcanza para compensar todas las facturas seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente.`

## Event and projector changes

Add to movement create/update payloads:

```elm
allocationIntent : Maybe AllocationIntent
```

Update:

- `Accounting.Movement`
- `Accounting.Form`
- `Events.MovementCreatedData`
- `Events.MovementUpdatedData`
- `Events.eventEncoder`
- `Events.eventDecoder`
- `Projector.projectEvents`
- `Ledger.movementDecoder` for cached movements
- `Update.Movements.persistMovement`

Create pure allocation/status module:

- `src/InvoiceAllocation.elm` or `src/Accounting/Allocation.elm`

Suggested exposed API:

```elm
module InvoiceAllocation exposing
    ( Allocation
    , AllocationStrategy(..)
    , AutoSelectionReason(..)
    , DocumentSettlement
    , DocumentStatus(..)
    , TargetSelectionSource(..)
    , allocate
    , invoiceSettlementFor
    , creditNoteSettlementFor
    , resolveAutoTargets
    )
```

Core pure functions:

```elm
resolveAutoTargets : List Movement -> Movement -> AllocationIntent
allocate : List Movement -> List Allocation
invoiceSettlementFor : List Allocation -> Movement -> DocumentSettlement
creditNoteSettlementFor : List Allocation -> Movement -> DocumentSettlement
```

Exact signatures can change during implementation; the important constraint is that allocation/status logic is pure and heavily tested.

## Migration/import notes

This feature needs to support future imports from older ad-hoc customer schemas.

Migration principles:

- Preserve imported explicit links when present.
  - `targetSelectionSource = MigrationSelectedTargets MigrationImportedExplicitTargets`
- Infer by document number when reliable.
  - `MigrationInferredFromDocumentNumber`
- Infer by exact amount/same account/date ordering when document numbers are missing.
  - `MigrationInferredFromExactAmount`
- Convert old `relatedToInvoice = True` without targets using a migration pass rather than silently dynamic allocation.
  - `MigrationInferredFromLegacyBoolean`
- Keep a migration report/log of unresolved cashflows or credit notes.

Avoid:

- Letting legacy targetless related cashflows dynamically reallocate every time new documents are added, unless the user explicitly chooses that compatibility mode.
- Storing derived status from legacy systems as source-of-truth. Import facts/links and recompute status locally.

## Tests

### Strategy and decoder tests

- Strategy strings decode to `AllocationStrategy` variants.
- Unknown strategy fails clearly or defaults only in explicit compatibility paths.
- Target selection source/reason round trips through JSON.
- Missing `allocationIntent` decodes as `Nothing`.

### Auto-target resolution tests

- Expense with no selected targets exact-matches an invoice with same account and remaining due.
- Expense does not match invoices from a different account.
- Income with no selected targets exact-matches a credit note with same account and remaining due.
- No exact match selects all open same-account eligible documents.
- No candidates stores `AutoNoCandidates` and produces warning state.
- Exact-match tolerance is `1 USD` or equivalent ARS using the cashflow rate.

### Allocation fold tests

- Allocates oldest due first.
- Continues to next selected document when first becomes full.
- Applies excess only to the oldest selected document.
- Does not allocate to unselected documents.
- Uses movement date then ID ordering for multiple cashflows.

### Currency tests

- ARS payment fully pays USD invoice using payment exchange rate.
- USD payment partially pays ARS invoice using payment exchange rate.
- Status is computed in target document currency.
- Display currency does not affect allocation results.

### Credit note tests

- Credit note offsets invoice directly.
- Credit note creation requires at least one target invoice.
- Credit note target invoice must share account.
- Credit note target invoice must share currency.
- Fully paid invoice becomes overpaid when a credit note is later associated and no refund exists.
- Refund income allocated to credit note reduces effective credit offset and settles invoice overpayment.
- Credit note can be partially refunded and partially applied to invoices.
- Credit note labels use `Aplicada` family when no refund movements exist and `Reembolsada` family when refund movements exist.

### Period semantics tests

- Invoice due in previous month and paid this month does not appear in this month's invoice table totals.
- Same payment appears in this month's cashflow table.
- Previous month's invoice table can show ledger-wide paid status after the later payment.

### Description UX tests

- Related expense with one selected invoice generates `Pago factura N`.
- Related expense with multiple selected invoices generates plural description.
- Related expense with missing document numbers falls back to `Pago facturas`.
- Related income generates `Cobro nota de crédito N`.
- Related income with missing document numbers falls back to `Cobro notas`.

## Implementation steps

1. [x] Add allocation union types and JSON encoders/decoders.
2. [x] Extend `Movement`/`Form` with `allocationIntent`.
3. [ ] Add UI state and picker wiring for invoice/credit-note selections.
4. [ ] Implement save-time auto-target resolution with source/reason audit fields.
5. [ ] Generate descriptions from selected/resolved documents for related cashflows.
6. [ ] Add credit-note invoice picker with same-account and same-currency validation.
7. [x] Build pure allocation/status module.
8. [x] Integrate ledger-wide statuses into invoice table rows.
9. [x] Adjust invoice period summaries to aggregate displayed documents only.
10. [ ] Add pre-save warning messages for over/under allocation.
11. [x] Update export to include statuses and remaining due.
12. [ ] Add migration helpers/reporting for legacy related cashflows.
13. [ ] Add tests listed above. (Partial: allocation projector and invoice report tests are in place.)
14. [ ] Validate after each checkpoint:
    - [x] `nix run .#format -- --validate` after invoice report/status checkpoint
    - [x] `nix run .#test` after invoice report/status checkpoint
    - [x] `nix run .#review` after invoice report/status checkpoint
    - [x] `nix run .#build` after invoice report/status checkpoint

## Remaining rough edges

No blocking product questions remain. Credit notes are still the highest-risk part of this plan, so implementation should lean on small pure functions and example-heavy tests rather than clever UI assumptions.

Watchouts during implementation:

1. Credit-note offsets are same-currency only, while cashflow allocations can be cross-currency.
2. Credit notes are mandatory invoice adjustments, not free-floating credits.
3. A refunded credit note reduces the credit available to offset invoices; this is what settles the overpayment created when a credit note arrives after an invoice was already fully paid.
4. Period invoice summaries include documents by due date, but statuses are ledger-wide.
