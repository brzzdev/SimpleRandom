# A Deck's writes are serialised, not compensated for

A Deck's pool is a `@FetchAll` over the Items with no draw row, and the row that removes a dealt card is written from a task. So there is a window between a deal and the pool catching up with it, and a re-roll arriving inside that window draws from a pool still offering a card the deck has spent — on the Lists path a repeat the user can see, and on the Combine path a second `ComboDraw` row landing silently, since `comboDraws` is keyed on a surrogate id rather than the Item.

**The window is closed by refusing to draw while a Deck write is in flight**, not by tracking what the pool has not caught up with. One `@StoreTaskID` covers both the deal's insert and Reshuffle's delete, and both buttons — **Again** and **Reshuffle** — no-op while it is running. `deal(_:)` already awaits the write and then the reload, so once its task settles the pool is authoritative; the guard is what makes that guarantee reach the pick.

The pool is then the only record of what a Deck has dealt, which is the rule `CONTEXT.md` already states: a Deck draws only over Items with no draw row, and is exhausted when none are left. There is no second place for that fact to live and no second place for it to be wrong.

## Why not a local guard

Six attempts preceded this. Five are preserved unmerged on `fix(randomise)/stale-pool-guard` (tip `4bf492c`), each adding state to the feature recording what it had dealt and filtering the draw against it:

| Attempt | Failed because |
| --- | --- |
| `c6322e4` — a set of dealt ids, cleared by Reshuffle | Outlived its window: a Reshuffle on another device could not reach the open sheet |
| `94be24d` — clear each id when its write settles | Cleared a committed card whose reload threw, and could not tell *which* deal of a card it was settling |
| `c3e59b6` — intersect the guard with the pool on reload | A failed write guarded its card for the life of the sheet; a remote Reshuffle kept a guard it should have dropped |
| `5346910` — settle per deal, keyed on a generation token | Nothing cleared a guard whose reload threw |
| `4bf492c` — sweep on every landed reload | The sweep reads a pool it cannot date, and is never reached when the deck exhausts |

**They share one root: every one of them answers "is the pool fresh enough to trust?", and that is not answerable from inside the feature.** `@FetchAll` refreshes from database observations as well as from explicit `load()` calls, and exposes no version — so "fresh" is not an observable property of the value the reducer is holding. Each fix moved which ordering breaks rather than removing the class of bug, and the two residuals it left were not cosmetic:

- **A Reshuffle on another device could not reach an open sheet.** Deck state syncs and Reshuffle is meant to put the cards back everywhere, but the remote delete refilled a pool the sheet then filtered right back down — answering "That's the whole deck" over a full deck until it was closed.
- **A write that failed spent its card anyway.** The guard was written before persistence started and the failure path removed nothing, so a one-card Deck reported exhaustion at a row count of zero. New behaviour, and worse than what preceded it: a failed write used to leave the card in the deck, which is correct.

The design here never asks the question. It refuses to pick while the answer could be no, and both residuals vanish rather than move — a remote Reshuffle refills the pool and the sheet simply believes it; a failed write inserts nothing, so the card is still there.

**A sixth attempt, rejected in design: pick and record in one transaction.** Reading the undealt candidates inside the write, choosing there and inserting the row would delete the window rather than compensate for it — but a plain draw records nothing, so it forces either a pointless write on the plain path or a second synchronous selection path beside it. ADR-0016 exists precisely so that the pool, the pick and exhaustion are implemented once across both surfaces and both modes. It would also cost the synchronous, pure `State.draw()` that ADR-0011 and ADR-0016 put in the reducer so a test can seed the generator, and ADR-0021's separation of the pick from the row's write.

## Consequences

- **Taps during a Deck write are swallowed silently**, matching the four guards of this shape already in the app (`ItemEditor.save`, `ListEditor.save`, `ComboEditor.save`, and Reshuffle's own). There is no visible disable: `StoreTaskID.isRunning` reads a plain `final class`, not an `@Observable` one, so a view reading it would not re-render when it flips. A visible disable needs a `State` flag plus a settle action clearing it on both paths — the shape of mechanism this decision removes. If swallowed taps prove perceptible, that is a measured follow-up.
- **A Reshuffle issued while a deal is in flight is refused**, which also fixes a defect never reported: previously the delete could remove every row and *then* have the in-flight insert land, stranding one spent card in a deck the user had just put back.
- **`.deckReshuffled` is deliberately not guarded.** It is sent from inside the reshuffle's own task, so the write is still in flight when it arrives and a guard there would refuse the very draw Reshuffle exists to produce.
- **The plain path is unaffected without a branch saying so.** `deal(_:)` returns before it reaches a task when the draw mode is not `.deck`, and a plain List has no Reshuffle — so nothing is ever attached to the id and **Again** is never gated (ADR-0004).
- **The orderings stopped being testable because they stopped existing.** The earlier attempts each needed a test asserting some interleaving of write, reload and tap; there is no interleaving left to assert. What became reachable instead are two consequences of the pool — "a failed write leaves its card in the deck" and "exhaustion tracks the row count" — both now asserted against a database whose inserts are refused. The in-flight guard itself stays untested for the reason `ItemEditor` already documents: a `TestStore` runs the first effect to completion before delivering the second action, so a test written against it passes with the guard removed.
- **`CONTEXT.md` is unchanged.** Serialisation is invisible in the domain: it changes no rule about what a Deck is or when it is exhausted, only how fast the button can be tapped. ADR-0021 is likewise untouched — the pick and the reveal remain the same instant, and the row is still written at the reveal.
