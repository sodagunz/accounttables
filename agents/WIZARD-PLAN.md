# Wizard and Local-First Onboarding Plan

## Goal

Reduce first-run friction without pretending local-only data is as safe as synced data.

Users should be able to:

- Start using the app without signing in.
- Keep core single-user data in `localStorage`.
- See clear, repeated reminders that local-only data can be lost.
- Sign in with Google when ready and migrate their local ledger to Firestore.
- Skip setup steps at any point and reach the working app.

Collaboration and cloud backup are the only features that remain unavailable while signed out:

- Inviting members requires Google sign-in and a Firestore ledger.
- Firestore sync/backup requires Google sign-in.
- Multi-ledger collaboration requires Google sign-in.

Everything else should work locally.

## Difficulty

Medium-large.

The wizard UI itself is straightforward. The larger work is making signed-out mode a real local-first mode instead of a demo-like state. Today, signed-out users can interact with parts of the app, but local account management and durable event persistence are not complete. We need a local ledger store, migration path, and product copy that is honest about data-loss risk.

## Product Shape

First run should show a skippable wizard:

1. Welcome / data safety
   - Primary action: `Ingresar con Google`
   - Secondary action: `Usar solo en este dispositivo`
   - Copy should be direct: local-only data is stored in this browser and can be lost if the browser storage is cleared, the device is lost, or the user switches devices.

2. Ledger name
   - Local default: `Libro contable de desconocido`
   - Signed-in default: `Libro contable de ${username}`
   - Works in both local and signed-in modes.
   - In signed-in mode, save to Firestore.
   - In local mode, save to local ledger state.

3. Accounts
   - Let users create the first accounts before entering movements.
   - Provide no mandatory defaults unless we decide on domain-specific defaults later.
   - This step must be skippable, but the movement form should still require an account before saving.

4. Collaborators
   - Only shown as an actionable invite step when signed in.
   - In local mode, show a disabled/educational state with `Ingresar con Google para invitar`.
   - Skippable in both modes.

5. Start working
   - Close the wizard and focus the amount field.
   - The app should remain fully usable after skipping.

## UX Rules

- The wizard must never block access to the main app permanently.
- Every wizard step has `Saltar`.
- Signed-out users should see a persistent but compact risk reminder, not a modal loop.
- The reminder should be stronger after local data exists.
- Avoid fear-heavy copy; be precise about risk.
- The app should not call local mode a backup. It is device-local storage.

Suggested reminder states:

- No local data yet: `Modo local: ingresa con Google para sincronizar.`
- Local data exists: `Datos solo en este dispositivo. Inicia sesión para respaldo y sincronización.`
- After several movements: stronger CTA in the header or admin panel, still dismissible for the session.

## Technical Design

### Local Ledger Store

Add a local ledger payload independent of Firebase auth:

```text
localStorage key: contabilizar:localLedger
schemaVersion: number
payload:
  status: "loaded"
  ledgerId: "local"
  ledgerName: string
  ledgers: one local summary
  accounts: Account[]
  events: Event[]
  expenses: []
  lastAccountId: string | null
  lastEventSequence: number
  updatedAt: ISO string
```

Use the existing event projection path for movements. Local mode should not use sample expenses once real local data exists.

### Elm Model

Add enough state to distinguish onboarding and storage mode:

```elm
type StorageMode
    = LocalOnly
    | CloudSynced

type WizardState
    = WizardNotSeen
    | WizardOpen WizardStep
    | WizardDismissed
    | WizardCompleted

type WizardStep
    = WelcomeStep
    | LedgerNameStep
    | AccountsStep
    | CollaboratorsStep
    | DoneStep
```

Model additions:

- `storageMode : StorageMode`
- `wizardState : WizardState`
- `localRiskDismissed : Bool`
- `localEventCountSinceReminder : Int`
- `hasLocalData : Bool`

Keep this small. Do not introduce a global route system unless needed.

### Ports

Add ports for local persistence:

- `loadLocalLedger`
- `localLedgerLoaded`
- `saveLocalLedger`
- `clearLocalLedger` after successful migration, only after confirmation/success.
- Optional: `markWizardSeen` if wizard state is stored separately.

Alternatively, local ledger can be loaded through existing flags at startup, but explicit ports make migration and saves clearer.

### Local Events

When signed out:

- `AddExpense` creates an event with a local sequence.
- The event is appended to `model.events`.
- Expenses are re-projected locally.
- `saveLocalLedger` persists the full local payload.

When signed in:

- Keep current Firestore `appendEvent` behavior.
- Continue using cached Firestore ledger payloads.

### Local Accounts

Update account management to work without auth:

- `AddAccount` in local mode creates a local account id and appends it to `model.accounts`.
- `DeleteAccount` in local mode soft-deletes the account locally and persists the local ledger.
- The current signed-out error messages in `Update.Accounts` should become mode-aware instead of auth-only.

This is required because a useful local-first accounting flow cannot depend on Firestore accounts.

### Local Ledger Name

`SaveLedgerName` should work in local mode:

- Update `model.ledgerName`.
- Update the synthetic local ledger summary.
- Persist local ledger payload.

In signed-in mode, keep current Firestore rename behavior.

### Invites and Members

Keep invite behavior cloud-only:

- Hide or disable invite form when signed out.
- If shown, copy should say Google sign-in is required for collaborators.
- Do not create local collaborators.
- Do not attempt to merge local collaborators during migration.

### Migration to Firestore

When a local-only user signs in:

1. Authenticate with Google.
2. Ensure personal Firestore ledger exists.
3. If local data exists, show a migration prompt before overwriting UI state:
   - `Subir datos locales a Google`
   - `Mantener datos de Google`
   - `Cancelar`
4. If user uploads local data:
   - Rename Firestore ledger to local ledger name if the user confirms.
   - Create missing local accounts in Firestore.
   - Append local events to Firestore in order.
   - Reload Firestore ledger.
   - Clear local ledger only after successful upload.

Migration can be implemented in a first version as "append all local events into the signed-in personal ledger". A later version can support conflict resolution or separate ledger creation.

Important: never silently discard local data on auth state change.

## Implementation Steps

1. [x] Define local-first data contract

   Finalize the local ledger payload shape and schema version. It should reuse the existing `Ledger.decodeLedger` format where possible so startup hydration can share the Firestore cache path.

2. [x] Add local ledger JS helpers

   Implement `loadLocalLedger`, `saveLocalLedger`, and `clearLocalLedger` around `localStorage`. Include schema validation, corruption handling, and `updatedAt`.

3. [x] Add Elm storage mode and wizard state

   Extend `Model`, `init`, and `Main.update` with `StorageMode`, `WizardState`, and messages for opening, skipping, advancing, and completing the wizard.

   Progress: `StorageMode`, `WizardState`, wizard messages, and persisted wizard dismissal/completion are implemented.

4. [x] Replace signed-out sample behavior with local ledger hydration

   On signed-out startup, load local ledger if it exists. Only show sample/empty state when there is no local data. Do not wipe local data on `SignedOut`.

5. [x] Make local account management work

   Update `Update.Accounts` and `Main.update` so signed-out users can add/delete accounts locally. Persist after each change.

6. [x] Make local movement persistence work

   Update add/edit/delete movement flows so signed-out users append local events and persist the local ledger. Keep Firestore append behavior unchanged for signed-in users.

7. [x] Make local ledger rename work

   Allow signed-out users to rename their local ledger. Persist the name and local ledger summary.

8. [x] Add the wizard UI

   Build a compact modal or full-screen panel for first-run setup. Steps: welcome, ledger name, accounts, collaborators, done. Every step has skip. The primary Google action should use the existing `signInWithGoogle` port.

9. [x] Add persistent local-risk reminder

   Add a small banner/status near the header when `storageMode == LocalOnly`. Escalate copy once local data exists or after a threshold such as 3 movements.

10. [x] Gate collaboration UI

   Keep members/invites unavailable in local mode. Show a clear sign-in CTA instead of broken controls.

11. [x] Add sign-in migration prompt

   When auth changes from local data to signed-in, prompt before replacing local state with Firestore data. First implementation can support upload-to-personal-ledger only.

12. [x] Implement local-to-Firestore upload

   Add a JS port or reuse Firestore helpers to create accounts and append local events in order. Clear local data only after a successful reload confirms the upload.

13. [ ] Add tests or verification checklist

   Cover at least:
   - Fresh signed-out user can skip wizard and use app.
   - Signed-out account add/delete persists across refresh.
   - Signed-out movement add/edit/delete persists across refresh.
   - Signed-out invite UI is unavailable.
   - Sign-in with local data does not discard local data.
   - Upload local data to Firestore preserves accounts and movements.
   - Existing signed-in users still load Firestore ledgers normally.

## Suggested Release Slices

### Slice 1: Honest Local Mode

- [x] Local ledger storage.
- [x] Local accounts.
- [x] Local movements.
- [x] Local risk reminder.
- No wizard yet beyond maybe a simple first-run choice.

This is the foundation. Without it, a skippable wizard would lead users into a weak local experience.

Started implementation:

- Local data is stored under `contabilizar:localLedger`.
- Signed-out and Firebase-unconfigured states use `ledgerId = "local"`.
- Local account add/delete, ledger rename, and movement add/edit/delete persist through `localStorage`.
- Collaboration remains cloud-only; signed-out users see a Google sign-in CTA in the members area.
- Migration from local data to Firestore is implemented. A single target ledger uploads automatically; multiple target ledgers show a selector before upload.

### Slice 2: Wizard

- First-run wizard UI.
- Ledger naming.
- Account setup.
- Collaborator step gated behind sign-in.
- Skip/dismiss behavior.

### Slice 3: Migration

- Detect local data on sign-in.
- Prompt to upload.
- Upload accounts/events to Firestore.
- Clear local data only after success.

### Slice 4: Polish

- Better reminder timing.
- Better migration conflict handling.
- Optional "export local backup" before migration.
- Optional onboarding analytics if privacy posture allows it.

## Recommendation

Build this in the release-slice order above.

Do not start with the wizard UI alone. The wizard is only valuable if choosing `Usar solo en este dispositivo` leads to a durable local workflow. The first implementation should make local mode real, then layer the wizard on top.
