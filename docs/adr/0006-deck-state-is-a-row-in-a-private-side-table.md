# Deck state is a row per dealt Item, in a private side table

A Deck deals each Item at most once. That state is stored as **the existence of a row** — `ListDraw` for a List's deck, `ComboDraw` for a Combo's — never as a column on the Item. Reshuffle deletes the rows.

```
ListDraw
  itemID     UUID  PRIMARY KEY and FK → Item(id) ON DELETE CASCADE
  createdAt  Date  when the Item was dealt
```

An Item belongs to exactly one List, so its own id identifies the draw and no separate `id` or `listID` is needed. A Combo's table needs both ids, because an Item can belong to many Combos.

The first design was `Item.drawnAt: Date?`, and it survived a whole ticket before being replaced. Two reasons overturned it, one of which has nothing to do with sync.

**One mechanism, not two.** A Combo's deck could never have been a column on `Item`, so the Lists tab and the Combine tab had independently arrived at two mechanisms for one concept. Both are now "a row per dealt Item, whose existence is the draw, deleted by Reshuffle".

**A per-user field on a shared record.** `CloudKitSharing.md` is explicit that only records with no foreign keys can be shared as a root, and `List` is exactly that shape — so a `List` is the thing anyone would one day share, carrying its `Item`s along. `drawnAt` sitting on `Item` means my draw deals your card, not as a choice but as a consequence. The library's answer is `privateTables`, whose prescribed shape is a side table with its foreign key as its primary key. **`ListDraw` is declared private from day one**, which changes nothing in v1 — private tables still sync across one person's devices.

## Consequences

- The timing mattered. Under ADR-0003's rule, a reserved column that has never been written can be relocated later for free; deck state is written on every tap, so moving it after ship would be a live data migration under a shared schema. This had to be decided before the first build or not at all.
- Sharing (`CKShare`) remains out of scope. This does not decide it — it stops v1 from quietly making it expensive.
- Deck state **syncs**: dealing on one iPhone leaves it dealt on the other. A Deck is a stateful object, not a view preference. Device-local deck state is worse than it looks, because sync is opted into per table rather than per column, so it would mean an unsynced table that no synced table may reference — orphan rows to filter forever. And a deck that resets when you pick up a different phone is not a deck.
- Under field-wise last-writer-wins, two devices drawing offline can lose one draw's worth of information. The failure mode is "an Item you never saw got skipped", not data loss.
- **A draw row is written when the result is shown, not when it is computed.** In v1 those are the same instant; see ADR-0021 for why the distinction is recorded anyway.
- Nothing else resets a Deck. No launch-based or timer-based reset — that is a scheduling feature wearing a randomiser's clothes. Adding an Item to an exhausted Deck silently un-exhausts it; editing an Item's title does not clear its draw, because identity is the row and not the text; switching a Deck back to plain preserves the rows, so switching back resumes.
