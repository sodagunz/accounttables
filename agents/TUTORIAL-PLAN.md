# Tutorial (product tour) — implementation plan

Replace the existing setup wizard with a spotlight-style interactive tutorial that guides the user through their first workflow.

## UX pattern

A full-viewport overlay with a semi-transparent backdrop dims everything except a highlighted target element. A tooltip bubble (attached near the target) explains what to do and provides navigation buttons. The user cannot interact with the dimmed app — only the tutorial controls are active.

On mobile the tooltip bubble always sits at the bottom of the screen (no repositioning needed).

## Tutorial steps

Each step targets an existing UI element. The user must click the tutorial's "Siguiente" to advance (except the last step which completes the tutorial).

| Step | Target element | Tooltip text | Action |
|---|---|---|---|
| 1 — Sign in | `Ingresar con Google` button | "Primero, inicia sesión con Google para sincronizar tus datos entre dispositivos." | User presses the real button (highlighted and clickable through overlay); auth state change advances to step 2. |
| 2 — Accounts | `Nueva cuenta` input field | "Crea una cuenta para empezar a registrar movimientos. Las cuentas pueden ser efectivo, bancos, billeteras virtuales, etc." | User types a name and presses `Agregar cuenta` (both highlighted). Tutorial watches for account creation; when at least one account exists, "Siguiente" appears. |
| 3 — Collaborators | Invite input / `Ingresar con Google` | "Puedes invitar colaboradores por email si trabajas con alguien más. O puedes saltar este paso." | Optional — "Saltar" moves forward; if signed in, user can invite then press "Siguiente". |
| 4 — First expense | `Descripción` input | "Vamos a registrar el primer movimiento. El importe y la descripción ya están completados. Solo presiona Guardar." | Form is pre-filled with `amount: 1000, description: "Venta de prueba"`. The `Guardar` button is highlighted. After the expense is created, step advances. |
| 5 — Delete expense | Delete button (`×`) on the newly created expense | "¡Perfecto! Ahora borrémoslo para que todo quede limpio. Presiona el botón ×." | Delete button on the just-created expense is highlighted. After deletion, tutorial completes. |
| 6 — Done | *(none — banner)* | "¡Listo! Ya sabés cómo funciona. Podés empezar a cargar tus movimientos reales." | Completion banner (same as current wizard-done-banner). |

### Edge cases

- **Already signed in:** Skip step 1 automatically.
- **Accounts already exist:** Skip step 2 automatically.
- **Both signed in AND accounts exist:** Skip to step 4.
- **Reopening the tutorial later:** Always start from step 1 (but skip steps whose precondition is already met, same logic).

## Architecture

### Types (`Model.elm`)

```elm
type TutorialStep
    = SignInStep
    | AccountsStep
    | CollaboratorsStep
    | FirstExpenseStep
    | DeleteExpenseStep

type TutorialState
    = TutorialOpen TutorialStep
    | TutorialDismissed
    | TutorialCompleted
```

Replace the current `WizardState`/`WizardStep` types with these. The existing `wizardState` field and `wizardCompletionVisible` are renamed/replaced.

### Ports (`Main.elm`)

**`getElementRect : String -> Cmd msg`** (Elm → JS)  
Sends a CSS selector string. JS calls `getBoundingClientRect` on the matching element and sends back coordinates.

**`elementRectReceived : { id : String, rect : { top, right, bottom, left, width, height } } -> msg`** (JS → Elm)  
Received dimensions used to position the spotlight cutout and attach the tooltip.

**`saveTutorialState : Encode.Value -> Cmd msg`** (replaces `saveWizardState`)  
Persists `"dismissed"` / `"completed"` / `""`.

### JS (`index.html`)

Replaces the current `loadWizardState` / `saveWizardState` with equivalent functions for tutorial state. Adds a handler for `getElementRect`:

```js
app.ports.getElementRect.subscribe((selector) => {
    const el = document.querySelector(selector);
    if (!el) return;
    const rect = el.getBoundingClientRect();
    app.ports.elementRectReceived.send({
        id: selector,
        rect: { top: rect.top, right: rect.right, bottom: rect.bottom, left: rect.left, width: rect.width, height: rect.height },
    });
});
```

### Overlay & tooltip (CSS / Elm)

The tutorial overlay is an absolutely-positioned `div` covering the full viewport (`position: fixed; inset: 0; z-index: 1000`).

**Spotlight cutout** — A `box-shadow` on an inner element creates the "hole" effect:
```css
.tutorial-spotlight {
    position: fixed;
    pointer-events: none;
    z-index: 1001;
    box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.45);
    border-radius: 6px;
    transition: all 0.25s ease;
}
```

The spotlight div is positioned at the target element's coordinates (received via port). The target element itself becomes `position: relative; z-index: 1002` so it renders above the dimming overlay — but we can skip that and instead just render the spotlight with `pointer-events: none` so the actual target element underneath stays clickable. Actually, the overlay blocks all clicks. We need to explicitly allow clicks on the target. Two approaches:

1. **Render the spotlight with `pointer-events: none`** and wrap it in an overlay that has `pointer-events: auto`. Then give the target element a high z-index so it sits above the overlay's backdrop. This is the cleanest approach but requires the target to have a stacking context.

2. **Use `pointer-events: none` on the entire overlay backdrop** and rely on the tooltip to block interaction. The user can still click anywhere (including non-target areas), which defeats the purpose.

I recommend **approach 1** — the overlay has a full-screen backdrop div + the spotlight div + the tooltip div. The backdrop (`z-index: 1000`) blocks clicks globally. The target element gets elevated to `z-index: 1002` (via a temporary class added by the tutorial). The spotlight (`z-index: 1001`, `pointer-events: none`) is purely visual. The tooltip (`z-index: 1002`) sits above everything.

**Tooltip bubble** — Positioned relative to the spotlight. On desktop it floats near (above/below/left/right) the target. On mobile it's at the bottom of the viewport. Contains:
- Step text (short paragraph)
- "Atrás" button (hidden on first step)
- "Siguiente" button (hidden on last step — replaced by "Finalizar")
- "Saltar" link

### Tutorial view (`Main.elm`)

When `tutorialState` is `TutorialOpen step`:
- The entire `<main>` content (including topbar) is rendered normally — the tutorial overlay sits on top via a `portal`-style div appended at the end of `.app`.
- The tutorial view renders the spotlight and tooltip with the current step's selector and text.
- On each navigation click (`WizardNext`, `WizardBack`), Elm emits the new step's selector via `getElementRect` to reposition the spotlight.
- On `WizardSkip`, state is set to `TutorialDismissed` and persisted.
- When `FirstExpenseStep` is entered, the expense form is pre-filled with the demo data and the form's msg handlers are active. The user fills out the form normally. On successful expense creation, tutorial advances.
- The tutorial does NOT use a separate `targetElementClass` approach — instead it sends the CSS selector of the current target to JS, which returns the live bounding rect.

### Step targeting (selectors)

| Step | CSS selector | Notes |
|---|---|---|
| SignInStep | `[data-tutorial="sign-in"]` | Add `data-tutorial` attr to the sign-in button. |
| AccountsStep | `[data-tutorial="account-name"]` | Add `data-tutorial` attr to the account name input. |
| CollaboratorsStep | `[data-tutorial="invite-email"]` | If signed in; else use `[data-tutorial="sign-in"]` for the Google button. |
| FirstExpenseStep | `[data-tutorial="description"]` | The description input in the expense form. |
| DeleteExpenseStep | `[data-tutorial^="delete-"]` | The delete button on the just-created expense. The selector includes the expense ID. |

### Mobile

On `max-width: 520px`:
- The spotlight cutout is smaller/simpler (maybe a full-screen dim with no cutout — just the tooltip at the bottom).
- The tooltip is fixed at `bottom: 0; left: 0; right: 0` with rounded top corners, no positioning logic needed.

## Implementation order

1. [x] **Add `data-tutorial` attributes** to target elements in the Elm views (`AuthStatus`, `ExpenseForm`, `ExpenseTable`).
2. [x] **Replace `WizardState` / `WizardStep`** with `TutorialState` / `TutorialStep` in `Model.elm`.
3. [x] **Add `getElementRect` / `elementRectReceived` ports** in `Main.elm`.
4. [x] **Write the tutorial overlay HTML & CSS** — backdrop, spotlight, tooltip.
5. [x] **Write JS handler** for `getElementRect` and the port round-trip.
6. [x] **Replace wizard view** with tutorial view — step content, navigation, spotlight positioning.
7. [x] **Wire up the auto-advance logic** — watching for account creation, expense creation/deletion, auth state.
8. [x] **Replace persistence** — `saveTutorialState` / `loadTutorialState` in JS.
9. [x] **Remove old wizard code** — wizard panel CSS, wizard messages.
10. [x] **Mobile pass** — verify tooltip at bottom, overlay works, spotlight optional.
11. [ ] **Test all edge cases:** already signed in, already has accounts, reopen dismissed, skip from each step, browser resize during tutorial.

## File changes summary

| File | Change |
|---|---|
| `src/Model.elm` | Replace `WizardStep`/`WizardState` with `TutorialStep`/`TutorialState`. Rename fields. |
| `src/Main.elm` | Replace wizard ports, messages, update cases, view with tutorial equivalents. Add `getElementRect`/`elementRectReceived`. Add data-tutorial attrs to target elements. Remove `wizardView`, `wizardStepContent`, etc. |
| `src/View/ExpenseForm.elm` | Add `data-tutorial="description"` attribute. Expose prefill via a `tutorialPrefill` config field or a dedicated msg. |
| `src/View/ExpenseTable.elm` | Add `data-tutorial` attribute to the delete button of each row. |
| `src/View/AuthStatus.elm` | Add `data-tutorial="sign-in"` to the sign-in button. |
| `public/index.html` | Replace `loadWizardState`/`saveWizardState` with `loadTutorialState`/`saveTutorialState`. Add `getElementRect` handler. |
| `public/index.css` | Add overlay, spotlight, tooltip styles. Remove wizard-panel styles. Mobile: tooltip at bottom. |
