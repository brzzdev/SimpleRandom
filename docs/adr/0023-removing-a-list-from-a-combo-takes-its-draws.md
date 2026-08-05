# Removing a List from a Combo takes that Combo's draws of its Items

Unticking a member List in the Combo form deletes that Combo's `ComboDraw` rows for the Items of the List that left, in the same transaction as the membership delete. Only that Combo's, and only those Items': every other Combo holding the same Items keeps its own memory of them, and no `ListDraw` row is touched (ADR-0007).

The question only exists because a Combo can be a Deck. Before that, a Combo had no rows to orphan.

## Considered options

- **Leave the rows.** Rejected, though it is the closer analogy: switching a Deck back to plain preserves its rows so that switching back resumes where it left off, and this would have been the same rule for membership. But `Item.undealt(inCombo:)` excludes an Item with *any* row for the Combo, pooled or not, so a List dropped and re-added would return with its Items already dealt — a deck that shrank for a reason the user has no way to see, because nothing on screen ever showed those rows.
- **Sweep stale rows on read**, or on launch. Rejected: a periodic delete of synced records is the kind of write that is hard to reason about from any one device, and it makes the moment a card is forgotten depend on when an app happened to run.

## Consequences

The line this draws is that **draw mode is how a Combo deals; membership is what it deals from.** Changing how you deal does not spend or unspend a card. Changing what is in the deck removes those cards, and their history goes with them. Two rules in the same paragraph of `CONTEXT.md` that would otherwise read as an inconsistency, and would be "fixed" back by someone who had not read this.

**Editing membership now destroys deck state, hard and globally.** Untick Films, save, and this Combo's memory of the Films Items it dealt is gone on every device, with no confirmation. That is consistent with every other write in this app — deletes are hard and sync-propagating (see **Sync**) — and with the form's existing behaviour, which already drops the membership rows themselves the same way. Deleting a List outright reaches the same end by cascade, on both surfaces at once.

**It is not a correctness guarantee, and the arithmetic still cannot lean on it.** The cleanup runs on the device doing the unticking. A second device unticking offline deletes the `ComboList` row and nothing tells the first to clear the draws, so stale rows remain a legal steady state under ADR-0008. `ComboSummary.index` therefore keeps its Item-conditioned join and `ComboDraw.pooled(in:)` keeps its subquery — both of which this decision otherwise appears to make redundant, which is exactly why the code says so where they are declared.

Reshuffle is unchanged and still deletes `ComboDraw.inCombo(_:)` — every row of that Combo's, stale ones included. It is the only thing that clears a row left behind by the offline path.
