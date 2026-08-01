# Shared screens are extracted; the two tabs stay peers

`ListsFeature` and `CombineFeature` are peers. Neither depends on the other. Every screen both of them present is extracted into its own target instead — which is how the graph reached twelve targets rather than the ten it was first drawn with.

Three extractions, each forced by the same rule and each arriving from a different direction:

- **`RandomiseFeature`** — both tabs present the result sheet, and it owns the draw rather than just its presentation (ADR-0016).
- **`ListDetailFeature`** — a Combo's member row pushes the *real* List detail, not a copy or a read-only preview, so the screen cannot live inside `ListsFeature` without `CombineFeature` importing the whole Lists index to reach it. The rejected alternatives were exactly that import, and a read-only item preview owned by `CombineFeature` that shows Items it cannot change.
- **`Components`** — the same peer problem at view scale. `EmojiField` is rendered by the List editor and the Combo form, the index row by both indexes, and the pinned Randomise bar by both detail screens. What justifies the target is not reuse for its own sake: each of the three carries accessibility treatment (ADR-0018) that decays in whichever copy nobody snapshots.

Index and detail otherwise stay in one target per tab — they share state and vocabulary, and splitting them is where cross-target chatter would concentrate. Finer splits in sibling apps reflect genuinely separate windows; this app is three tabs, one or two levels deep.

## Consequences

`Preferences` earns a target for two `@Shared(.appStorage)` keys, which is thin — but the alternative is a `UserDefaults` key string written in two targets with no compiler check, and `hasCompletedFirstFetch` is *written* by the sync delegate in `Database` and *read* by both index tabs. That is exactly the drift the target prevents.

Sync wiring lives in `Database` alongside `migrator` and `appDatabase()`: the tables list and `privateTables: [ListDraw.self]` are schema facts, not app facts, and putting them in `App` would place them in the one target no test can reach. `App` stays a thin launch shim.

`Acknowledgements` is its own target because `Licenses.generated.swift` is regenerated on every dependency bump, and behind its own target that rebuild does not dirty Settings' logic or tests.

`Components` holds views and no logic, so it carries no tests; `ListDetailFeature`'s behaviour is exercised through `ListsFeatureTests` (ADR-0019).
