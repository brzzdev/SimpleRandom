# Reserve unread columns from the first shipped build

`deletedAt`, `position`, `updatedAt` and `weight` ship in v1's schema and are read by nothing. This looks like dead weight and is deliberate: ADR-0002 makes the CloudKit schema append-only from the first shipped build, so reserving a column is free now and impossible later.

Applied to every table, join tables included — `ComboList.position` is the column a future "reorder a Combo's Lists" would want.

## Considered options

- **Add columns when they are needed.** The normal answer, and unavailable: a rename or a relocation is not permitted once the schema is deployed, so "when needed" means "never, cleanly".
- **Reserve nothing and version the schema.** Migration under a synced CloudKit schema is itself unresolved and post-ship work; this avoids needing it for the four most likely requests.

## Consequences

`position` is the likeliest v1.x request (drag to reorder). `deletedAt` is next — v1 deletes are hard and unrecoverable (ADR-0009), and undo is the obvious thing to be asked for afterwards. It is reserved on `List`, `Item`, `Combo` and `ComboList` — everything whose removal is a user gesture — and deliberately **not** on `ListDraw` or `ComboDraw`, where the only deletion is Reshuffle. Reshuffle is designed as a hard delete, and a `deletedAt` there would quietly break the arithmetic that decides whether a Deck is exhausted.

The rule that makes this safe also draws its boundary: **a reserved column that has never been written is free to relocate later**, because there is no data to migrate — only a dead column left behind, which append-only permits. That is why `position` can stay on the record despite a future `CKShare` wanting it in a side table, and why deck state could not (ADR-0006).
