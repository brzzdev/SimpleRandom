# Combo membership is a join table, not an array column

The Combine tab holds saved **Combos** — a named set of member Lists, and the unit a pooled randomise runs over. A Combo references its member Lists by id through a `ComboList` join table, so it stays live as those Lists gain, lose and rename their Items. No snapshot, no copy.

This redrew an earlier framing, in which the Combine tab was an ad-hoc tick-list with no `Combo` table at all. That version had nowhere of its own to store deck state, which is what forced the question and then the entity.

## Considered options

- **A `[UUID]` column on `Combo`.** Rejected on ADR-0002's conflict rule: resolution is field-wise last-writer-wins, so two devices each adding a different List offline means one edit is silently lost. Rows merge; arrays do not. A join table also cascades memberships away when a List is deleted, instead of leaving a dangling id to filter at read time forever.
- **A nullable `drawnAt` on the join table**, doubling as deck state. Rejected: rows would accumulate for every Item ever drawn and never leave, and "row exists but `drawnAt` is nil" is a second way to spell undealt (see ADR-0006).

## Consequences

The graph is `Combo ──< ComboList >── List ──< Item` plus `Combo ──< ComboDraw >── Item` — acyclic, every foreign key `ON DELETE CASCADE`, so ADR-0002's validation accepts it. `Combo` mirrors `List` exactly, reserved columns included: one vocabulary across both tabs.

No `UNIQUE` is available outside the primary key, so duplicate `ComboList` rows for the same List are possible from concurrent offline edits, and the pool **deduplicates by `listID`** when it is built. Without that, a List's weight silently doubles.

Deleting a List cascades its memberships away and the Combo silently shrinks, with no warning. A confirmation on the Lists tab enumerating affected Combos costs more than the surprise it prevents.

`Combo`, `ComboList` and `ComboDraw` can never be shared — records with multiple foreign keys are excluded by the sync layer, without workaround. Accepted: a Combo is a personal arrangement of your own Lists, not a thing to hand to someone else.
