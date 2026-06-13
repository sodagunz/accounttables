# UI Plan

1. [x] Mobile-first expense entry

   The default layout should be designed from the phone screen upward. The first viewport should prioritize the movement form and the latest expenses, with controls sized for touch and arranged vertically. Desktop can add density later, but the mobile version should not feel like a collapsed desktop table.

2. [x] `Registrar movimiento` as the main visible feature

   The primary action on the screen is registering a movement. Supporting features can exist, but they should not visually compete with the entry form. The page should make it obvious that the user can open the app, enter an amount, and record an expense immediately.

   Implemented by making the application header more compact and styling the movement form as the primary work surface. The movement panel now has stronger hierarchy, the amount field has more visual weight, and the submit button spans the form. Ledger, caja, and invitation controls remain visible for now because hiding them belongs to later plan items.

3. [x] Amount-first entry flow

   Amount is the only field that should demand attention on a repeated entry path. Caja, currency, and date should have useful defaults, while description stays secondary. This makes the form behave like a quick capture tool rather than a bookkeeping worksheet.

   Implemented by keeping `Importe` as the first control in the form, adding autofocus to it, and adding mobile/browser input hints so phones open a decimal numeric keyboard. The form still leaves caja, currency, date, and description available, but the first interaction is now explicitly optimized around amount entry.

4. [x] Make description optional

   Description is not required to register a movement. The field should stay available as secondary input, but the fast path must work with only amount, caja, currency, and date. Empty descriptions are stored as `Nothing`/`null` and displayed as `-`.

   Verified end to end. `Expense.description` is modeled as `Maybe String`, `buildExpense` accepts an empty description and stores it as `Nothing`, Firestore encoding writes `null`, decoding reads nullable descriptions, and table/export rendering falls back to `-`. No code changes were required for this item.

5. [x] Keep description secondary

   Description should not appear before amount in the form and should not slow down the default entry flow. Users can add it while entering a movement, but the UI should also support adding or editing it later from the table.

   Implemented by keeping description below amount, currency, caja, and date, and giving it lighter visual treatment than the primary movement controls. The field remains available during entry, but it no longer reads as part of the critical path. Later table editing is intentionally left out of this item because it needs its own interaction design.

6. [x] Empty descriptions represented as `-`

   Empty descriptions need a consistent visual placeholder so table rows keep their structure and exports stay readable. Use a single `-` instead of blank cells, muted explanatory text, or generated labels. The placeholder means “no description was provided”, not “unknown data”.

   Implemented with a shared `descriptionDisplay` formatter used by both the expense table and export payloads. It renders `Nothing`, empty strings, and whitespace-only descriptions as exactly `-`, while leaving real descriptions unchanged.

7. [ ] Expense-only movement model for now

   The UI can use the broader word `movimiento`, but every movement created by the current form is an expense. We should avoid exposing income/transfer controls until the model and UX are ready for them. This keeps the product behavior simple while leaving room for future movement types.

8. [ ] Positive user-entered `inputAmount`

   Users should never need to type a minus sign for expenses. The amount field accepts the natural number they see on a receipt or bill, and the accounting sign is derived internally. This is friendlier for non-accounting users and avoids accidental double negatives.

9. [ ] Negative computed cashflow through `movementType = "Expense"`

   The app should compute signed cashflow from `movementType` plus the positive `inputAmount`. For the current expense-only flow, `movementType = "Expense"` means ARS and USD cashflow values are stored as negative numbers. This separates user input from accounting semantics.

10. [ ] Hide ledger creation by default

Ledger creation is administrative and infrequent, so it should not compete with expense entry on the default screen. Use a compact top bar that shows the current ledger name and exposes ledger switching/creation through a clearly labeled control, such as `Libro contable`, rather than a generic hamburger menu. On mobile this can open a bottom sheet; on desktop it can open a popover or side panel.

11. [ ] Hide caja/account management by default

    Caja management is closer to configuration than daily entry. Keep the selected caja visible in the movement form, but move create/delete/rename actions into a secondary `Cajas` section inside the settings/admin area. This keeps the entry flow fast while still making caja setup discoverable when someone needs to adjust the ledger structure.

12. [ ] Hide workspace invitations by default

    Invitations are ownership/admin actions, so they should live behind an explicit `Miembros` or `Invitaciones` section in the same settings/admin area. Avoid putting invite controls in the main navigation or expense entry surface. The main screen can show no invite UI unless there is a pending state that directly affects access, such as an invite acceptance prompt.

13. [ ] Keep new movement entry to at most two clicks after typing

    After typing an amount, the user should be able to submit without touching any other field in the common case. The target flow is: type amount, tap `Registrar movimiento`. A second click is acceptable only when changing a default such as caja or currency; repeated same-context entry should stay one submit action after typing.

14. [ ] Default caja to the last used caja

    The selected caja should persist after each movement so repeated entries do not require re-selection. If there is no previous selection, choose a sensible default such as the first active caja, while still making the selected caja visible enough to prevent silent misclassification.

15. [ ] Default currency to the last used currency

    Currency should behave like caja: preserve the last selected value after submitting. This matters because people often enter a batch of receipts in the same currency. Resetting to ARS after every submit creates friction and risks wrong entries for USD-heavy sessions.

16. [ ] Default date behavior

    The initial date should be today. During a session, retaining the currently selected date is useful for entering multiple movements from the same day or from a backlog. The UI should make the date visible and easy to change without making it part of the critical path for today’s expenses.

17. [ ] Mobile expense table placement

    On mobile, recent expenses should appear immediately below the entry form. This gives quick confirmation that the movement was recorded and supports fast correction if the user notices a wrong caja, currency, date, or missing description. Filters and exports should not push the latest rows too far down.

18. [ ] Large-screen form and table layout

    On wider screens, place the entry form and table in the same working area. The form can sit in a narrower left column while the table uses the wider right side for scanning and comparison. This should feel like an operational tool, not a landing page or stacked marketing layout.

19. [ ] Secondary settings/admin area

    Ledger management, caja management, and invitations should be grouped in one explicit secondary area. The trigger can be a top-bar control such as `Administrar` or a settings icon with a clear label. Inside, use sections or tabs for `Libro contable`, `Cajas`, and `Miembros`, rather than scattering admin controls across the main expense screen.

20. [ ] Default screen priority

    The default screen should answer one question first: “what do I need to enter now?” Recent expenses are the second priority because they provide confirmation and correction. Everything else should be reachable, but subordinate to fast expense capture and review.
