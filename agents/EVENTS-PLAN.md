# Event Sourcing Plan

## Schema

```
ledgers/{ledgerId}
  ├── nextEventSequence: number  (atomically incremented)
  ├── ...existing fields...
  │
  └── events/{autoUuidV7}        ← NEW subcollection (source of truth)
       ├── eventType: string     ("movement_created" | "movement_deleted" | "movement_updated")
       ├── sequence: number      (monotonically increasing, 1-based)
       ├── data: object          (event-specific payload)
       ├── createdAt: Timestamp  (server timestamp)
       └── version: number       (schema version, starts at 1)
```

Event payloads:

```
movement_created.data → { movement: { id, movementType, description, accountId, accountName,
                            inputAmount, inputCurrency, exchangeRate, ars, usd, date } }
movement_deleted.data   → { movementId: string }
movement_updated.data   → { movementId: string, changes: { ...partial fields } }
```

## Steps

1. [x] Create `src/Events.elm` — event union types, event encoder, event decoder

2. [x] Create `src/Projector.elm` — `List Event -> List Expense` (pure projector)

3. [x] Add `nextEventSequence` to the Firestore ledger document (via migration or on next write)

4. [x] Add JS `appendEvent` port handler — uses `runTransaction` to atomically increment `nextEventSequence` and write the event doc with UUIDv7 doc ID

5. [x] Add JS `loadEvents` port handler — reads all events from `ledgers/{ledgerId}/events` ordered by `sequence`, includes in `ledgerLoaded` payload

6. [x] Update Elm `Model` — add `events : List Event` (expenses still from direct Firestore fetch, not yet derived via projection)

7. [x] Update Elm `Main.elm` — on `EventsLoaded`: project events to expenses; on expense add: build `MovementCreated` event, send to `appendEvent` port (dual-write alongside `saveExpense`)

8. [x] Update `Ledger.elm` decoders — add all event decoders via `Events.eventDecoder`, update `LedgerData` to carry events

9. [x] Switch read side: replace direct expense fetching with event-based projection; remove `saveExpense`

10. [ ] Update localStorage caching — cache the projected read model + `lastEventSequence` for incremental sync

11. [x] Add `MovementDeleted` event and delete expense flow

12. [x] Add `MovementUpdated` event and edit expense flow

13. [x] Migration — not needed (fresh start)

## Notes

- **UUIDv7**: Generated on JS side via the existing `uuidv7()` helper, used as the Firestore document ID. Queries order by `__name__` for chronological order.

- **Transaction**: `runTransaction` ensures gapless sequences by atomically reading then incrementing `nextEventSequence` on the ledger document.

- **Projection**: Always runs locally in Elm (pure function). localStorage caches the projected model + last seen sequence. On page load: use cached model from flags, then fetch only events beyond that sequence.

- **Versioning**: Each event carries a `version` field so the projector can handle schema evolution.
