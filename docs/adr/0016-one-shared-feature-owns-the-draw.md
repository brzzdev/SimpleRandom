# The result sheet is one shared feature that owns the draw

`RandomiseFeature` is presented by both tabs and owns the whole draw, not just its presentation. Its state carries a `DrawScope` — `.list(List.ID)` or `.combo(Combo.ID)` — and the feature builds the pool, picks, writes the `ListDraw` or `ComboDraw` row, detects exhaustion and reshuffles.

Re-roll and Reshuffle are both buttons on the sheet, so the logic follows the gestures — and one test suite covers both tabs' deck arithmetic instead of the same arithmetic being implemented and tested twice.

**Only the detail screens present it.** `randomise: RandomiseFeature.State?` hangs off `ListDetail` and `ComboDetail`; there is no Randomise button on an index row. You open a List, then randomise it — the screen you are on is unambiguously the thing being drawn from, and Reshuffle sits next to the Items it acts on.

## Consequences

- **One sheet serves both paths.** The Lists path shows the drawn Item alone; the Combine path adds a single secondary line above it carrying the source List's emoji and name, which ADR-0004 makes load-bearing. Nothing else differs — same detent, same single button, same exhausted-Deck treatment.
- **The pool lives in `RandomiseFeature.State`**, as a `@FetchAll` whose query is built from the `DrawScope`, rather than being assembled inside the reducer at draw time and discarded. This is only ADR-0011's read rule applied, but it is also the thing that keeps a future reveal animation possible (ADR-0021), because the sheet is a child feature whose view can see no other state. It is not free: in Deck mode the remaining pool shrinks on every draw, so exhaustive `TestStore` assertions carry that churn alongside the result.
- **State also carries `drawToken`**, an `Int` incremented per draw and rendered by nothing — the only value a re-roll landing on the same Item changes, and therefore the only thing the haptic and the announcement can trigger on (ADR-0017). Not persisted.
