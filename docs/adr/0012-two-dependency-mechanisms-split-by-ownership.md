# Two dependency mechanisms, split by ownership

The app uses `@FeatureEnvironment` for everything it owns, and `@Dependency` only for what crosses into SQLiteData — the database and the random number generator.

Two mechanisms in one app looks like indecision, so the line is worth stating. `@FeatureEnvironment` is ComposableArchitecture 2's native mechanism: 23 uses across its `Examples/`, zero `@Dependency`. Its own documentation frames swift-dependencies as "an alternative … suited to applications that need to share dependencies across non-ComposableArchitecture features and paradigms" — which is precisely SQLiteData, a library with no knowledge of this one that reads `DependencyValues` on its own.

## Consequences

This is what makes ADR-0001's `Dependencies` trait load-bearing rather than a preference: without it the store never re-establishes `DependencyValues` around feature work, and every override set at store creation silently fails to apply.

The split gives a test for new dependencies: if SQLiteData or another external library reads it, `@Dependency`; if the app defines it, `@FeatureEnvironment`.
