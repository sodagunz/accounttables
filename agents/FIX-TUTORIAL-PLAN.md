# Fix Tutorial Plan

## Recommendation

Do not continue polishing the current hand-rolled rect/overlay implementation. Replace the browser geometry and spotlight layer with a purpose-built tour library, while keeping Elm responsible for product state and workflow decisions.

The product direction is a **spotlight tutorial**, not an onboarding wizard or setup panel. The tutorial should teach very non-technical users how to navigate the real application while they configure it. The app UI should remain recognizable behind the tour, and each step should point at the actual control the user needs to learn.

Recommended library: **Driver.js**.

Reasons:

- Vanilla JS, so it fits the current static `public/index.html` architecture.
- MIT licensed and free for commercial use.
- Small, zero-dependency package.
- Supports product tours, single highlights, configurable popovers, custom button behavior, hooks, refresh/redraw, keyboard behavior, and active-target interaction.
- The current branch is already reimplementing Driver.js-style responsibilities by hand: target measurement, overlay cutout, target elevation, tooltip placement, scroll/body locking, and step hooks.

Avoid Shepherd.js and Intro.js unless licensing is explicitly accepted. Their current docs describe AGPL/commercial licensing.

Relevant docs:

- Driver.js configuration: https://driverjs.com/docs/configuration
- Driver.js API: https://driverjs.com/docs/api
- Driver.js npm/license summary: https://www.npmjs.com/package/driver.js
- Shepherd.js usage: https://docs.shepherdjs.dev/guides/usage/
- Shepherd.js license: https://docs.shepherdjs.dev/guides/license/
- Intro.js license: https://introjs.com/docs/getting-started/license
- Floating UI positioning reference: https://floating-ui.com/docs/computeposition

## Branch Strategy

Work on the dedicated `fix-tutorial` branch, which was created on top of the existing `tutorial` history.

Why:

- The current branch history captures the real failure modes: target availability, pointer events, disclosure state, scroll/body lock, mobile behavior, auth timing, and step-specific affordances.
- A cleanup commit can remove the brittle implementation and replace it with a clearer boundary.
- The dedicated branch keeps the refactor isolated without discarding the history that explains why the hand-rolled approach failed.

## Current Problems

The current approach is too manual and fragile.

Concrete issues found in the branch:

- `getElementRect` sends one `getBoundingClientRect()` result, but the tooltip is not recomputed on resize, scroll, layout shift, target resize, or tooltip content resize.
- Elm ignores the selector/id returned with the rect, so a delayed rect can be applied after the tutorial has moved to another step.
- Tooltip placement only checks whether the target is above or below the viewport midpoint. It does not measure tooltip dimensions or prevent right/left/bottom overflow.
- `.tutorial-overlay` has `pointer-events: none`, so the overlay no longer blocks non-target app interaction.
- Mobile hides both spotlight and backdrop, so the tutorial becomes only a bottom tooltip while the full app remains clickable.
- `.tutorial-target` is elevated with z-index. This creates stacking-context risk and can let large highlighted elements visually compete with the tooltip.
- `DeleteExpense` always persists tutorial completion, even when the deleted expense is unrelated to the tutorial.
- `DeleteExpenseStep` targets the first active expense, not specifically the demo expense created by the tutorial.
- The first expense step is not actually prefilled as described in `TUTORIAL-PLAN.md`.
- Reopening behavior no longer always starts from sign-in and then skips based on preconditions.
- The branch accumulated many compensating commits after the overlay landed, which is a signal that the architecture is carrying too many browser-layout responsibilities.

## Target Architecture

Keep this split:

- Elm owns tutorial state, app state, persistence, and workflow rules.
- JS owns tour rendering, target measurement, overlay geometry, popover placement, resize/scroll refresh, and DOM-only concerns.

Elm should not store viewport rects or manually position tooltips.

Non-goals:

- Do not rebuild the setup wizard.
- Do not replace the tutorial with a compact checklist or first-run panel.
- Do not hide the application behind a separate onboarding screen.
- Do not make desktop the only polished experience. Mobile is the primary quality bar.

Mobile requirements:

- The tutorial must work end-to-end on a narrow mobile viewport.
- The active target must be visible and tappable when the step requires a real app action.
- The popover must not cover the primary action for the current step.
- The user should never need to understand technical app structure, scroll manually to hunt for targets, or guess which real control is being discussed.
- The overlay should keep non-target interactions blocked unless a step explicitly allows target interaction.

### Elm State

Keep:

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

Add:

```elm
tutorialExpenseId : Maybe String
```

Use `tutorialExpenseId` to target and delete only the demo movement created during the tutorial.

Remove:

```elm
tutorialTargetRect : Maybe TargetRect
```

Remove the `TargetRect` type entirely.

### Ports

Replace:

```elm
getElementRect : String -> Cmd msg
elementRectReceived : (Decode.Value -> msg) -> Sub msg
lockBodyScroll : Bool -> Cmd msg
```

With a smaller tour bridge:

```elm
port showTutorialStep : Encode.Value -> Cmd msg
port hideTutorial : () -> Cmd msg
port tutorialAction : (Decode.Value -> msg) -> Sub msg
```

Optional:

```elm
port refreshTutorial : () -> Cmd msg
```

Only use `refreshTutorial` if a step changes layout without changing step.

### Tutorial Step Payload

Elm sends a payload like:

```json
{
  "step": "first-expense",
  "selector": "[data-tutorial=\"movement-form\"]",
  "title": "",
  "description": "El importe y la descripcion ya estan completos. Presiona Guardar.",
  "side": "right",
  "align": "start",
  "showBack": true,
  "showNext": false,
  "showSkip": true,
  "done": false,
  "allowTargetClick": true
}
```

JS renders this with Driver.js and emits actions back:

```json
{ "action": "next" }
{ "action": "back" }
{ "action": "skip" }
{ "action": "done" }
{ "action": "target-missing", "step": "accounts" }
```

Elm maps those to existing `TutorialNext`, `TutorialBack`, `TutorialSkip`, and `TutorialFinish` logic.

## Driver.js Integration Plan

1. Add Driver.js assets.

   For the current static app, use pinned CDN assets in `public/index.html`, matching the existing CDN style already used for Firebase and SheetJS:

   ```html
   <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/driver.js@1.3.6/dist/driver.css" />
   <script src="https://cdn.jsdelivr.net/npm/driver.js@1.3.6/dist/driver.js.iife.js"></script>
   ```

   If the project later moves to a bundled JS setup, install `driver.js` and import it instead.

2. Add JS tour adapter functions in `public/index.html`.

   Responsibilities:

   - Create a singleton Driver.js instance.
   - Render one Elm-requested step at a time with `driverObj.highlight(...)` or a one-step `setSteps(...); drive()`.
   - Configure Spanish button labels.
   - Disable overlay-close behavior unless product wants click-out-to-skip.
   - Allow interaction with the highlighted target for steps that require real app clicks.
   - Emit button events back through `tutorialAction`.
   - Call `driverObj.destroy()` on completion/dismissal.
   - Call `driverObj.refresh()` after disclosures open or after layout-affecting app events.

3. Remove custom overlay/spotlight view from Elm.

   Delete:

   - `tutorialView`
   - `tutorialTooltipPosition`
   - `TargetRect`
   - `ElementRectReceived`
   - `tutorialTargetRectDecoder`
   - manual spotlight CSS
   - `.tutorial-target` class logic

4. Keep `data-tutorial` attributes.

   They are useful and should remain as the stable contract between Elm-rendered views and JS tour rendering.

5. Move disclosure state toward Elm where practical.

   Best option: model admin/accounts/members disclosure open state in Elm and render `Html.Attributes.attribute "open" ""` conditionally.

   Acceptable short-term option: keep `openDisclosure`, but sequence it before showing the Driver.js step and refresh the tour afterward.

6. Fix tutorial workflow bugs.

   - `TutorialSkip` should be explicit per step. Do not reuse `advanceTutorialFrom` blindly if product copy says "dismiss" or "skip this optional step".
   - `DeleteExpense` should only save `"completed"` when `model.tutorialState == TutorialOpen DeleteExpenseStep`.
   - Store the created tutorial expense id when the first tutorial movement is created.
   - Target `[data-tutorial="delete-${tutorialExpenseId}"]`, not the first active expense.
   - If the tutorial-created expense no longer exists, skip delete and complete cleanly.
   - Reopen from `SignInStep`, then skip steps whose preconditions are already met.

7. Prefill the first movement step.

   When entering `FirstExpenseStep`, set the form to:

   ```elm
   amount = "1000"
   description = "Venta de prueba"
   movementType = IncomeMovement
   ```

   Use the current selected account, or the first active account.

   The tooltip should say the fields are already filled and the user should press the real submit button.

8. Make mobile deterministic and first-class.

   Driver.js can handle placement, but product behavior should be explicit:

   - On small screens, prefer a bottom-sheet-style popover through CSS override.
   - Keep the overlay active unless the current step deliberately allows target interaction.
   - Avoid target cutouts that hide essential controls under the fixed bottom popover.
   - Ensure Driver.js scrolls the target into view before showing the popover.
   - Add mobile-specific placement rules per step when needed. For example, a bottom popover may work for account creation, but the movement form may need the submit button above the popover before the user taps it.
   - Test with realistic mobile heights, not only desktop browser responsive mode.

9. Add a small manual QA checklist.

   Test cases:

   - Fresh signed-out user.
   - Signed-out user skips Google and creates local account.
   - Already signed-in user with no accounts.
   - Already signed-in user with accounts.
   - Already has accounts and reopens tutorial.
   - Skip from sign-in.
   - Skip collaborators.
   - Browser resize during each step.
   - Mobile viewport through the full flow.
   - Create demo expense, then delete only that expense.
   - Existing real expenses remain untouched.

## If Driver.js Fails

If Driver.js cannot satisfy the mobile interaction requirements, the fallback is **still a spotlight tutorial**, not a wizard or panel. Move all geometry to JS and use Floating UI or browser observers.

Minimum custom fix:

- JS owns tooltip and spotlight positioning.
- Use `ResizeObserver`, `window.resize`, scroll listeners, and `requestAnimationFrame` to refresh while the tutorial is open.
- Use `computePosition`/`flip`/`shift`/`autoUpdate` from Floating UI, or implement equivalent overflow handling.
- Keep overlay pointer events blocking the app.
- Create explicit click tunnels only for the active target, or attach target click handlers in JS.
- Validate stale selector ids before applying geometry.
- Remove z-index target elevation unless absolutely required.

This is more work than using Driver.js and still less battle-tested.

## Proposed Implementation Order

1. Add Driver.js assets and JS adapter.
2. Replace rect ports with tutorial action/show/hide ports.
3. Remove custom Elm overlay and CSS.
4. Add `tutorialExpenseId`.
5. Fix first-expense prefill and delete targeting.
6. Fix persistence guards.
7. Add mobile-specific Driver.js/CSS behavior.
8. Run `nix develop -c elm make src/Main.elm --output=/tmp/contabilizar-elm.js`.
9. Perform the manual QA checklist above, with mobile checked before desktop.
