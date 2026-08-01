# A `tca26` branch of BrzzUtils, rather than vendoring one file

`View Logs` needs the `\.osLogStore` dependency, which lives in `brzzdev/BrzzUtils`. BrzzUtils depends on `swift-composable-architecture` 1.26.1 and therefore on `swift-case-paths` **by version**; TCA26 pins that same package to `branch: "26"`. SPM cannot satisfy a branch pin and a version range for one package, so depending on BrzzUtils as it stands is a resolution failure, not merely a second copy of TCA in the graph.

The answer is a long-lived `tca26` branch of BrzzUtils: the whole package, with `swift-composable-architecture` swapped for TCA26's `ComposableArchitecture2`, the platform floor raised, and call sites moved to `@Feature` / `Update`. `main` is untouched and stays public; the `tca26` branch is only resolvable with TCA26 access, which is members-only.

Whole-package rather than a slice, so the two branches stay diffable and `main`'s fixes cherry-pick — and so the next TCA 2 app finds everything already ported.

## Considered options

**Vendor the one file into a local `LogsClient`.** Cheaper, and rejected: the port is wanted for its own sake, and a vendored copy is a fork with none of the diffability.

## Consequences

The branch must exist and build before SimpleRandom resolves. That work is in another repo and is a prerequisite for implementation rather than part of this spec.
