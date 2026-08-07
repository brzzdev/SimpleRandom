// swift-tools-version: 6.3
//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import PackageDescription

let package = Package(
	name: "SimpleRandom",
	// English only in v1 — but the catalogues ship from the first build, because
	// retrofitting one over a finished app is the expensive order. This is also what makes
	// SwiftPM treat each target's `Localizable.xcstrings` as a localisation resource, so no
	// target needs an explicit `resources:` entry. See ADR-0022.
	defaultLocalization: "en",
	// iPhone only, iOS 26 minimum. The floor is what unlocks ComposableArchitecture 2's
	// `StoreActor` and `TestStoreActor`, both `@available(iOS 26, *)`.
	platforms: [.iOS(.v26)],
	products: [
		// One product over the whole graph: the Tuist app target is the composition root
		// and reaches `App`, which reaches everything else.
		.library(name: "App", targets: ["App"]),
	],
	dependencies: [
		// No tags, no releases — a moving branch is the only thing to pin to (ADR-0001).
		//
		// `traits: ["Dependencies"]` is load-bearing, not cosmetic: without it the store
		// never re-establishes `DependencyValues` around feature work, so overrides set at
		// store creation silently do not apply — and SQLiteData is built on
		// swift-dependencies throughout.
		.package(url: "https://github.com/pointfreeco/TCA26", branch: "main", traits: ["Dependencies"]),
		// SQLiteData's `CasePaths` trait is deliberately left off. It forwards to
		// StructuredQueries' `CasePathsMacrosSupport`, which does not exist on the
		// `swift-case-paths` `26` branch that TCA26 pins the whole graph to. Leaving it off
		// costs only enum-table support, which this schema does not use.
		.package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.7.0"),
		.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
		// Named here only so the feature targets may `import SwiftUINavigation` for
		// `alert(item:)` and `confirmationDialog(item:)`, whose single-optional forms SwiftUI
		// still has no equivalent of. TCA26 already
		// depends on this package and pins this branch, so the resolved graph is unchanged —
		// the entry declares a dependency the app was already building against transitively.
		// The branch must stay in step with TCA26's, or resolution fails outright rather than
		// silently taking one of them.
		.package(url: "https://github.com/pointfreeco/swift-navigation", branch: "relax-sendable"),
		// Named here for the same reason as swift-navigation above: `Preferences` declares the
		// `theme` shared key and `App` reads it, so both name `Sharing` types in their own
		// source — and `Preferences` names one in its *public* API. SQLiteData and TCA26 both
		// already depend on this package, so the resolved graph is unchanged; the entry
		// declares a dependency the app was already building against transitively.
		.package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.9.0"),
	],
	targets: [
		.target(
			name: "Acknowledgements",
			dependencies: [
				.product(name: "ComposableArchitecture2", package: "TCA26"),
			],
		),
		.target(
			name: "App",
			dependencies: [
				"AppFeature",
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"Database",
				.product(name: "Dependencies", package: "swift-dependencies"),
				"Models",
				"Preferences",
				.product(name: "Sharing", package: "swift-sharing"),
			],
		),
		.target(
			name: "AppFeature",
			dependencies: [
				"CombineFeature",
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"ListsFeature",
				"SettingsFeature",
			],
		),
		.target(
			name: "CombineFeature",
			dependencies: [
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"Components",
				"Database",
				"ListDetailFeature",
				"Models",
				"Preferences",
				"RandomiseFeature",
				.product(name: "SwiftUINavigation", package: "swift-navigation"),
			],
		),
		.target(
			name: "Components",
			dependencies: [
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"Models",
			],
		),
		.target(
			name: "Database",
			dependencies: [
				"Models",
				.product(name: "SQLiteData", package: "sqlite-data"),
			],
		),
		.target(
			name: "ListDetailFeature",
			dependencies: [
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"Components",
				"Database",
				"Models",
				"RandomiseFeature",
			],
		),
		.target(
			name: "ListsFeature",
			dependencies: [
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"Components",
				"Database",
				"ListDetailFeature",
				"Models",
				"Preferences",
				"RandomiseFeature",
				.product(name: "SwiftUINavigation", package: "swift-navigation"),
			],
		),
		.target(
			name: "Models",
			dependencies: [
				.product(name: "SQLiteData", package: "sqlite-data"),
			],
		),
		.target(
			name: "Preferences",
			dependencies: [
				"Models",
				.product(name: "Sharing", package: "swift-sharing"),
			],
		),
		.target(
			name: "RandomiseFeature",
			dependencies: [
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"Components",
				"Database",
				"Models",
			],
		),
		// `BrzzUtils` is deliberately absent until `View Logs` lands (ADR-0015): it is the
		// one target gated on that package's `tca26` branch existing, and everything else
		// in the plan proceeds without it.
		.target(
			name: "SettingsFeature",
			dependencies: [
				"Acknowledgements",
				.product(name: "ComposableArchitecture2", package: "TCA26"),
				"Database",
				"Models",
				"Preferences",
				.product(name: "SwiftUINavigation", package: "swift-navigation"),
			],
		),
		// Four test targets, chosen by risk rather than by symmetry (ADR-0019). The other
		// eight targets carry none.
		// As the other three below: everything but `Database` and the suite trait arrives
		// through `CombineFeature`.
		//
		// `ListDetailFeature` and `RandomiseFeature` arrive that way too, but are named anyway:
		// this target is where `ComboDetail`'s pooled draw and its push of the real `ListDetail`
		// are exercised, and it `@testable`-imports both for the `DebugSnapshot` types. A
		// dependency a test target imports directly is one it should declare.
		.testTarget(
			name: "CombineFeatureTests",
			dependencies: [
				"CombineFeature",
				"Database",
				.product(name: "DependenciesTestSupport", package: "swift-dependencies"),
				"ListDetailFeature",
				"RandomiseFeature",
			],
		),
		// `DependenciesTestSupport` carries the suite trait that hands each test case its own
		// in-memory database, and is the only link this target needs beyond `Database` itself:
		// `Models` and `SQLiteData` arrive transitively, which is why they are not repeated.
		.testTarget(
			name: "DatabaseTests",
			dependencies: [
				"Database",
				.product(name: "DependenciesTestSupport", package: "swift-dependencies"),
			],
		),
		// As `DatabaseTests`: `DependenciesTestSupport` carries the suite trait that hands each
		// test case its own in-memory database, and `Database` is what builds one. Everything
		// else — `Models`, `SQLiteData`, ComposableArchitecture2 — arrives through
		// `ListsFeature`.
		//
		// `ListDetailFeature` arrives that way too, but is named anyway: this target is where
		// `ListDetail`'s behaviour is exercised (ADR-0019), and it `@testable`-imports it for
		// the `DebugSnapshot` types. A dependency a test target imports directly is one it
		// should declare.
		.testTarget(
			name: "ListsFeatureTests",
			dependencies: [
				"Database",
				.product(name: "DependenciesTestSupport", package: "swift-dependencies"),
				"ListDetailFeature",
				"ListsFeature",
				"RandomiseFeature",
			],
		),
		// As the two above: `DependenciesTestSupport` carries the suite trait that hands each
		// test case its own in-memory database, and `Database` is what builds one. The draw
		// reads its pool through a real `@FetchAll`, so it needs a real database even though
		// nothing here writes.
		.testTarget(
			name: "RandomiseFeatureTests",
			dependencies: [
				"Database",
				.product(name: "DependenciesTestSupport", package: "swift-dependencies"),
				"RandomiseFeature",
			],
		),
	],
)

// The strict regime, first of its two sites. The second is the Tuist app-target settings
// in `Project.swift` — the app shell is not exempt.
for target in package.targets {
	var settings = target.swiftSettings ?? []
	settings.append(contentsOf: [
		.enableUpcomingFeature("ExistentialAny"),
		.enableUpcomingFeature("ImmutableWeakCaptures"),
		.enableUpcomingFeature("InferIsolatedConformances"),
		.enableUpcomingFeature("InternalImportsByDefault"),
		.enableUpcomingFeature("MemberImportVisibility"),
		.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
	])
	#if compiler(>=6.4)
	settings.append(.treatAllWarnings(as: .error))
	#endif
	target.swiftSettings = settings
}
