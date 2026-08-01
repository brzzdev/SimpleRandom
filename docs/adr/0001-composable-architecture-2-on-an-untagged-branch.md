# ComposableArchitecture 2, tracked on an untagged branch

SimpleRandom is deliberately a showcase of ComposableArchitecture 2, taken as the `ComposableArchitecture2` product of the members-only `pointfreeco/TCA26` package. That package has zero releases and zero tags, so `branch: "main"` is the only way to depend on it — the resolved SHA is committed and the churn is accepted knowingly. Point-Free say outright they do not recommend shipping what you write with it; the app is small, personal and unreleased enough for that to be a fair trade against learning the library properly.

The 1.x vocabulary is **deleted, not deprecated**: `Reducer`, `Reduce`, `Effect`, `@ObservableState`, `@Presents`, `PresentationAction`, `BindingReducer`, `ViewStore`, `StackState`, `IdentifiedAction`, `AlertState` and `@Dependency(\.dismiss)` have zero occurrences in the module. Only `Scope` and `Store` survive. Anything written for TCA 1.x is a rewrite, not a migration.

## Consequences

- **The deployment target is iOS 26.** The library itself is iOS 17+, but `StoreActor` and `TestStoreActor` need 26. iPhone-only, no iPad, Mac or watch layouts.
- **Traits are `["Dependencies"]` and nothing else.** Without that trait the store never captures and re-establishes `DependencyValues` around feature work, and overrides set at store creation silently do not apply — which SQLiteData needs. `SwiftNavigation` is UIKit-only; `Clocks` propagates a clock this app has no timers for. Naming `traits:` at all replaces the package default of `ComposableArchitecture1Deprecations`, which costs nothing given the paragraph above.
- **SQLiteData's `CasePaths` trait stays off.** TCA26 pins `swift-case-paths` to `branch: "26"`, which lacks the `CasePathsMacrosSupport` target StructuredQueries needs under that trait. Point-Free's own answer on the issue is to pin an older StructuredQueries; leaving the trait off is cheaper, and costs only enum-table support, which the schema does not want. Re-verify at first resolve.
- **The local `pfw-composable-architecture-2` skill is stale**, bundled `.swiftinterface` included — it still declares `@FeatureLocal` and knows nothing of `@FeatureEnvironment`. The resolved checkout and its `Examples/SwiftUICaseStudies/` are the authority.
- The library's own churn is fast — `@FeatureLocal` was renamed within three days of landing. Exhaustive tests (ADR-0019) are what make that churn fail loudly instead of silently.
