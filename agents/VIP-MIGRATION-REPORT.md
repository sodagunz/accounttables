# VIP Furatti migration candidate report

Date: 2026-06-21
Ledger: `Q2zSif5DcoeBDSdauyEkFDOvpMt1`
Source export: `backups/vip-Q2zSif5DcoeBDSdauyEkFDOvpMt1.json`

## Scope

This report analyzes the ad-hoc invoice workflow around these two accounts:

- `Furatti` (`019ed04d-4298-7593-9e2a-f5c1b01b37bd`)
- `Furatti Factura` (`019ed0ba-219b-73d2-b0b9-64a96622626d`)

Assumption from product context:

- `Furatti Factura` was used as the ad-hoc invoice register.
- `Furatti` contains the real cashflow-side movements associated with those invoices.
- Some rows were edited/deleted during experimentation, so the event history contains abandoned attempts.

## High-level conclusion

`Furatti Factura` is the safest authoritative source for reconstructing documents:

- `Expense` rows on `Furatti Factura` look like supplier invoices.
- `Income` rows on `Furatti Factura` with `Pago ...` look like payment application evidence.
- `Income` rows on `Furatti Factura` with `Nota de credito ...` look like supplier credit notes.

`Furatti` is mixed:

- some rows are clearly the real cashflow counterpart,
- some are unrelated operational expenses,
- at least one active row appears inconsistent with the payment evidence and should be treated carefully.

## Active candidate source rows

### Candidate invoices from `Furatti Factura`

| Movement ID | Date | Type | Amount | Description | Candidate migration |
| --- | --- | --- | ---: | --- | --- |
| `019ed0bc-69a8-7c0b-a542-aa7518c1dc97` | 2026-05-30 | Expense | 6,465,930.38 ARS | `Factura 1575` | `SupplierInvoiceMovement` |
| `019ed0c2-1d85-7461-a513-dd6f07c80690` | 2026-05-31 | Expense | 4,181,520.13 ARS | `Factura 1580` | `SupplierInvoiceMovement` |

### Candidate payment / credit-note evidence from `Furatti Factura`

| Movement ID | Date | Type | Amount | Description | Candidate migration |
| --- | --- | --- | ---: | --- | --- |
| `019ed0bd-e009-79cb-bbe3-4120efba1305` | 2026-05-30 | Income | 3,200,000 ARS | `Pago 1575` | payment evidence |
| `019ed0c3-334a-7ac6-84d2-c34ddfb88a36` | 2026-05-31 | Income | 1,800,000 ARS | `Pago 1575` | payment evidence |
| `019ed0ca-79fe-7919-afde-2575eef1e226` | 2026-06-16 | Income | 3,000,000 ARS | `Pago 1580` | payment evidence |
| `019ed0cb-6900-7f26-834f-ab83b71220f3` | 2026-06-16 | Income | 163,326.45 ARS | `Nota de credito 68` | `SupplierCreditNoteMovement` |

### Candidate real cashflows from `Furatti`

Only the invoice-related-looking subset is listed here.

| Movement ID | Date | Type | Amount | Description | Candidate use |
| --- | --- | --- | ---: | --- | --- |
| `019ed0a2-a663-7962-a467-cde10f4b9c2b` | 2026-05-30 | Expense | 3,200,000 ARS | `Factura 1575` | likely payment cashflow counterpart for `Pago 1575` |
| `019ed0a6-d890-740a-bb15-3de827d31f00` | 2026-05-31 | Expense | 4,181,520.13 ARS | `Pago de facturas` | suspicious / unresolved |
| `019ed0cc-d126-763f-9c47-5f6630efd801` | 2026-05-31 | Expense | 1,800,000 ARS | `Pago de facturas` | likely payment cashflow counterpart for second `Pago 1575` |

Other active `Furatti` rows like `Sueldo Brai`, `Liquidacion Lurbe`, `Perfileria Juanchi Vidrios`, etc. look unrelated and should stay as normal cashflows.

## Deleted historical clues

These rows matter because they explain some of the inconsistencies in the final state.

### Deleted paired experiment around `1580 + 1575`

| Movement ID | Account | Date | Amount | Description | Status |
| --- | --- | --- | ---: | --- | --- |
| `019ed0c4-5dd7-755f-b935-97514a01c99d` | `Furatti Factura` | 2026-06-09 | 5,000,000 ARS | `Pago 1580 + 1575` | deleted |
| `019ed0b7-d88d-7b41-ba77-e87e24e08982` | `Furatti` | 2026-06-09 | 5,000,000 ARS | `Furatti 1580` | deleted |

Interpretation:

- there was likely an intermediate attempt to represent a combined payment of `5,000,000 ARS`,
- later replaced by the active split view (`1,800,000` for `1575`, `3,000,000` for `1580`),
- but the active `Furatti` cashflow side was not cleaned up consistently.

### Deleted noise rows on `Furatti Factura`

There are many deleted `VENTA` / `VENTAS` income rows in `Furatti Factura` from 2026-05-21 through 2026-06-19.

Recommendation:

- ignore them for invoice migration,
- treat them as experimentation noise unless the user explicitly says they matter.

## Candidate migration mapping

## 1. Invoice `1575`

### Proposed target document

Create:

- `SupplierInvoiceMovement`
- source: `019ed0bc-69a8-7c0b-a542-aa7518c1dc97`
- date: `2026-05-30`
- amount: `6,465,930.38 ARS`
- document number: `1575`
- account: `Furatti`

### Proposed related cashflows

Create cashflow allocations from the two `Furatti` expenses below to invoice `1575`:

| Cashflow movement | Amount | Why |
| --- | ---: | --- |
| `019ed0a2-a663-7962-a467-cde10f4b9c2b` | 3,200,000 ARS | amount and description line up with `Pago 1575` |
| `019ed0cc-d126-763f-9c47-5f6630efd801` | 1,800,000 ARS | amount lines up with second `Pago 1575` |

### Confidence

**High**

Reason:

- invoice document is explicit,
- payment evidence appears twice in `Furatti Factura`,
- matching real cashflow amounts exist in `Furatti`.

### Expected settlement after migration

- invoice nominal: `6,465,930.38 ARS`
- applied payments: `5,000,000 ARS`
- remaining due: `1,465,930.38 ARS`

## 2. Invoice `1580`

### Proposed target document

Create:

- `SupplierInvoiceMovement`
- source: `019ed0c2-1d85-7461-a513-dd6f07c80690`
- date: `2026-05-31`
- amount: `4,181,520.13 ARS`
- document number: `1580`
- account: `Furatti`

### Payment evidence

There is clear document-side evidence for one payment:

| Evidence movement | Amount | Description |
| --- | ---: | --- |
| `019ed0ca-79fe-7919-afde-2575eef1e226` | 3,000,000 ARS | `Pago 1580` |

### Candidate real cashflow counterparts

There is **no active `Furatti` expense for exactly `3,000,000 ARS`**.

The closest relevant rows are:

| Movement ID | Amount | Description | Assessment |
| --- | ---: | --- | --- |
| `019ed0a6-d890-740a-bb15-3de827d31f00` | 4,181,520.13 ARS | `Pago de facturas` | suspicious: equals the full invoice amount, not the payment amount |
| `019ed0b7-d88d-7b41-ba77-e87e24e08982` | 5,000,000 ARS | `Furatti 1580` | deleted historical experiment |

### Confidence

**Low / unresolved**

Reason:

- invoice exists clearly,
- payment evidence exists clearly,
- real cashflow counterpart is inconsistent in the final active state.

### Safer migration options

#### Option A — conservative

- create invoice `1580`,
- do **not** create a related payment cashflow automatically,
- surface `Pago 1580` as unresolved migration evidence for manual review.

#### Option B — heuristic

- create invoice `1580`,
- treat `019ed0a6-d890-740a-bb15-3de827d31f00` as the intended cashflow counterpart,
- allocate it to `1580`,
- accept that this would overpay the invoice by `1,181,520.13 ARS` relative to the `Pago 1580` evidence.

Recommendation: **Option A**.

## 3. Credit note `68`

### Proposed target document

Create:

- `SupplierCreditNoteMovement`
- source: `019ed0cb-6900-7f26-834f-ab83b71220f3`
- date: `2026-06-16`
- amount: `163,326.45 ARS`
- document number: `68`
- account: `Furatti`

### Invoice linkage

No explicit target invoice can be inferred safely from the active state alone.

Possible business guess:

- it may apply to `1575` or `1580`,
- but there is not enough evidence in the description alone to attach it automatically.

### Confidence

**Low / unresolved target**

Recommendation:

- create the credit note only if you are comfortable leaving it unresolved for manual targeting later,
- otherwise keep it out of the automatic pass and flag it for manual review.

## Proposed first migration pass

### Safe auto-migrate

1. Create invoice `1575`.
2. Create invoice `1580`.
3. Create related payment cashflow `3,200,000 ARS` to invoice `1575`.
4. Create related payment cashflow `1,800,000 ARS` to invoice `1575`.

### Do not auto-migrate yet

1. `Pago 1580` (`3,000,000 ARS`) — missing trustworthy `Furatti` cashflow counterpart.
2. `Nota de credito 68` — target invoice unresolved.
3. `Furatti` movement `019ed0a6-d890-740a-bb15-3de827d31f00` (`4,181,520.13 ARS`) — active but inconsistent.

## Suggested expand-contract strategy

1. Clone this ledger into a new test ledger.
2. Apply only the safe first pass above.
3. Keep all original movements untouched in the original ledger.
4. Review the resulting invoice table locally.
5. Decide manually how to treat:
   - the `3,000,000 ARS` `Pago 1580`,
   - the `163,326.45 ARS` credit note,
   - the suspicious `4,181,520.13 ARS` `Furatti` expense.
6. Only then generate the production migration payload.

## Open questions for manual review

1. Was `019ed0a6-d890-740a-bb15-3de827d31f00` meant to be:
   - the real payment of invoice `1580`,
   - a mistaken duplicate of the invoice amount,
   - or a row that should have been deleted?
2. Should `Nota de credito 68` reduce invoice `1575`, invoice `1580`, or remain separate?
3. Do you want unresolved items omitted from the automatic migration, or included in a partially migrated ledger with a manual-fix checklist?
