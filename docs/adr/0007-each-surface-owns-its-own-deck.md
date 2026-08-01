# Each surface owns its own deck

A Combo's draw is governed only by its own `drawMode` and its own `ComboDraw` rows. Member Lists' `drawMode` and `ListDraw` rows are neither read nor written. A Combo always pools **every** Item of every member List, including ones already dealt within their own List, and drawing from a Combo never writes a `ListDraw` row.

"Dealt in Movies" and "dealt in Friday night" are separate facts.

## Considered options

- **Nest the two deck states** — honour a member List's own deck when pooling. Rejected: the two compose into behaviour that is genuinely hard to predict, and an exhausted member List would silently shrink the pool with nowhere sensible to put its Reshuffle.
- **Honour `drawMode` per Item.** Rejected for the same reason plus a worse one — a pool that mixes plain Lists and Decks is not in one mode, so there is no coherent thing for the sheet to say.

## Consequences

This is the one thing about combining that is not guessable from the outside, so the Combo form's draw-mode footer says it in words: the Combo's Deck is "separate from each List's own deck".

It also settles a question the module graph would otherwise have had to answer twice. `ListDetail` is pushed from the Combine tab as well as the Lists tab (ADR-0014), and it **behaves identically wherever it is pushed** — its own pinned Randomise, its own editor sheets, its own `ListDraw` deck. A flag suppressing the button when presented from Combine was rejected: conditional behaviour on a shared screen, to prevent something this ADR has already declared legal.

Expect a test asserting `ComboDraw`'s independence from `ListDraw` in both directions; it is the rule most likely to be "fixed" by someone who has not read this.
