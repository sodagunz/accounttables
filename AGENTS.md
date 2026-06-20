# ContabilizAR — AGENTS.md

## Build & dev

```sh
nix run .#build              # default build (public/elm.min.js)
nix run .#build-release      # optimized + uglified
nix run .#run-local        # dev server on port 8008
nix run .#deploy             # firebase deploy
nix run .#format             # format src/ tests/ in place
nix run .#format -- --validate  # CI check (read-only)
nix run .#test               # run all tests
nix run .#review             # elm-review (lint)

nix develop          # enter dev shell
```

Enter dev env: `nix develop`.  
Serve from `public/`: `python3 -m http.server 8008` (or `nix run .#run-local`).  
Deploy: `nix run .#deploy` (runs `firebase deploy`).
Deploy: `nix run .#deploy` (runs `firebase deploy`).

`public/` is the Firebase hosting root (SPA rewrites to `/index.html`).  
`.gitignore` ignores `elm.js`, `public/elm*.js`, `.direnv/`, `.secrets/`.

## Architecture

- **Elm 0.19.1** single-page app, no Elm SPA framework.
- **Event-sourced**: events stored in Firestore (`ledgers/{id}/events`). Each event has a `sequence` field. `Projector.elm` projects events into current expense state. Events are immutable — editing produces a new `MovementUpdatedEvent` with the same `movementId`.
- **Ports** for all JS interop (Firebase auth, Firestore CRUD, file download, element rect queries, focus, scroll lock, disclosure open). No Elm ports library — raw `port` declarations in `Main.elm`.
- **Two-way reconciliation**: Firebase events cached in localStorage (`contabilizar:ledger:{uid}:{ledgerId}`). Cache written before Firestore transaction; merged on load. Event document IDs (UUIDv7) are the reconciliation key.
- **Main entrypoint**: `Main.elm` (port module). Model in `Model.elm`. Update distributed across `Update/` submodules. Views in `View/` submodules.

## Key quirks & gotchas

- `Accounts.add` does NOT add the account to the model's local list synchronously. It returns a `(Model, Maybe Encode.Value)` — the payload goes through a port round-trip. The account appears in the model only when `ledgerLoaded` fires back. Tutorial auto-advance after account creation must use `handleLedgerLoaded` / `adjustTutorialAfterLedgerLoad`, not the `AddAccount` handler.
- `data-tutorial` attributes on UI elements drive the tutorial spotlight. The JS `getElementRect` handler toggles `.tutorial-target` class (gives `z-index: 1000`) on only the current target.
- Tutorial step transitions clear `tutorialTargetRect` via `tutorialNavigateTo` helper before querying the new element's rect.
- The `tutorialMovementId` field in the model tracks the expense created during `FirstMovementStep` so the `DeleteMovementStep` can find its delete button via `[data-tutorial="delete-{id}"]`.

## Tutorial system

- `Tutorial.elm` is the main tutorial logic module. `Main.elm` wraps it with port config and inline view code (spotlight, tooltip via `tutorialView`).
- Steps: `SignInStep → AccountsStep → CollaboratorsStep → FirstMovementStep → DeleteMovementStep`.
- `stepAfterAccounts` skips `CollaboratorsStep` when not signed in.
- Disclosures (`admin-tool`, `accounts-tool`, `members-tool`) are auto-opened via `openDisclosure` port before rect query.
- The "Siguiente" button only appears on `CollaboratorsStep`; other steps auto-advance on user action or skip.
- The "Saltar" button skips one step ahead (advance, not dismiss). Hidden on `AccountsStep` and `DeleteMovementStep`.
- Spotlight uses `box-shadow: 0 0 0 9999px` cutout. On mobile (≤520px) the spotlight/backdrop are hidden, tooltip becomes a bottom sheet.

## Ports summary

| Port | Direction | Purpose |
|------|-----------|---------|
| `authStateChanged` | JS→Elm | Firebase auth state |
| `signInWithGoogle` | Elm→JS | Trigger Google sign-in popup |
| `signOutUser` | Elm→JS | Sign out |
| `loadLedgerData` | Elm→JS | Load ledger from Firestore/localStorage |
| `ledgerLoaded` | JS→Elm | Ledger data returned |
| `appendEvent` | Elm→JS | Save event to Firestore/localStorage |
| `saveAccount` | Elm→JS | Create account via Firestore |
| `deleteAccount` | Elm→JS | Soft-delete account |
| `generateExpenseId` | Elm→JS | Generate UUIDv7 |
| `expenseIdGenerated` | JS→Elm | UUIDv7 returned |
| `getElementRect` | Elm→JS | Query element rect for tutorial spotlight |
| `elementRectReceived` | JS→Elm | Rect + viewportHeight returned |
| `focusElement` | Elm→JS | Focus an input element |
| `openDisclosure` | Elm→JS | Open `<details>` by id |
| `lockBodyScroll` | Elm→JS | Lock/unlock body scroll for tutorial |
| `saveTutorialState` / `loadTutorialState` | Elm↔JS | Persist tutorial state to localStorage (`contabilizar:tutorialState`) |
| `exportTable` | Elm→JS | Download CSV/XLSX |
| `prepareLocalMigration` / `localMigrationPrepared` | Elm↔JS | Local→Firestore migration flow |

## Style conventions

- Spanish UI labels throughout.
- `printWidth: 100`, trailing commas (`.prettierrc.json`).
- Mobile-first responsive breakpoints: 820px, 520px.
- Primary green: `#17352c`. Negative values: `#b91c1c`.
