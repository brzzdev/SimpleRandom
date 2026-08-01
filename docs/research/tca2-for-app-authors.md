# ComposableArchitecture 2 — what it changes for app authors

Research for wayfinder ticket [#2](https://github.com/brzzdev/SimpleRandom/issues/2), a sub-issue of
the [v1 spec map](https://github.com/brzzdev/SimpleRandom/issues/1).

Target context, settled going in and not re-examined here: iPhone-only, iOS 26 deployment target,
Tuist wrapping a local SPM package with modular targets, `ComposableArchitecture2` depended on as a
product of the `TCA26` package pinned to `branch: "main"`, SQLiteData for persistence with iCloud
`SyncEngine`.

## Sources

Primary only. Nothing here comes from a blog post, forum summary, or third-party write-up.

- **`pointfreeco/TCA26`** — the beta repo itself (private, Point-Free members only; readable with the
  authenticated `gh` CLI). Analysed at commit `363d646019b82b74ebe4db7836d62992deb61c77` ("Fix main
  actor isolation issue", 2026-07-03), the tip of `main` at time of writing, cloned with full
  history. Cited below as **`TCA26@363d646`**. Covers `README.md`, `Package.swift`,
  `Sources/ComposableArchitecture2/`, its DocC catalog under
  `Sources/ComposableArchitecture2/Documentation.docc/`, `Examples/`, and `Tests/`.
- **`TCA26` GitHub issues and discussions**, queried live.
- **`pointfreeco/swift-case-paths`**, **`pointfreeco/swift-structured-queries`**,
  **`pointfreeco/sqlite-data`** — their `Package.swift` files, read from GitHub.
- **The local `pfw-composable-architecture-2` skill**, at
  `~/.claude-personal/skills/pfw-composable-architecture-2/`, comprising `SKILL.md` and
  `references/interface/ComposableArchitecture2.swiftinterface`.

> **⚠️ Read [§7](#7-the-local-pfw-composable-architecture-2-skill-has-drifted) before trusting the
> skill.** Both `SKILL.md` *and* its bundled `.swiftinterface` predate `main` by roughly two months
> and describe APIs that have since been renamed or superseded. The repo is the authority; the skill
> is not.

---

## 1. Package identity, product, and how pinnable it is

| Question | Answer | Source |
| --- | --- | --- |
| Repo URL | `https://github.com/pointfreeco/TCA26` | README, `TCA26@363d646` |
| SPM package name | `TCA26` | `Package.swift`, `name: "TCA26"` |
| Product to depend on | `ComposableArchitecture2` | `Package.swift` `products:` |
| Module to import | `import ComposableArchitecture2` | README; every file under `Examples/` |
| Version / tag | **None.** Zero releases, zero git tags. | `gh api repos/pointfreeco/TCA26/releases` → `0`; `.../tags` → `0` |
| What you pin to | `branch: "main"` (or a commit SHA) | Issue [#169] and the `ComposableArchitecture1` DocC page both use `branch: "main"` |
| Repo visibility | Private — Point-Free members only | `gh repo view pointfreeco/TCA26 --json isPrivate` → `true` |

Sibling products in the same package, relevant only for migration:

- **`ComposableArchitecture1`** — a 1.x-compatible module built *on top of*
  `ComposableArchitecture2`, so an existing 1.x app can compile against the new package while
  migrating.
- **`ComposableArchitecture`** — an alias target that re-exports `ComposableArchitecture1`.
- **`ComposableArchitectureTestSupport`** — test-only helpers, notably the `.environment(_:_:)`
  Swift Testing suite trait.

Source: `Package.swift` `products:` / `targets:`, `TCA26@363d646`.

### Package traits — the part that bites

`Package.swift` declares four traits and enables exactly one by default:

```swift
traits: [
  .default(enabledTraits: ["ComposableArchitecture1Deprecations"]),
  .trait(name: "Clocks", description: "Support for Clocks in the feature environment"),
  .trait(name: "Dependencies", description: "Propagate task-local Dependencies through the feature hierarchy"),
  .trait(name: "SwiftNavigation", description: "Add support for SwiftNavigation's UIBindings"),
  .trait(name: "ComposableArchitecture1Deprecations", description: "Turn on warnings for deprecated APIs"),
]
```

So `Clocks`, `Dependencies` and `SwiftNavigation` are **off unless you ask for them**
(`Package.swift`, `TCA26@363d646`).

The `Dependencies` trait is not cosmetic. In `Sources/ComposableArchitecture2/Internal/Core.swift`
the store captures `@Dependency(\.self) private var capturedDependencies` (line 910) and
re-establishes it with `withDependencies` around feature work (lines 173–192, 920–924) — all inside
`#if Dependencies`. Without the trait, dependency values in scope where the store was created are
**not** re-applied when feature logic later runs, and the `.dependency(_:_:)` /
`.transformDependency(_:transform:)` feature modifiers don't exist at all
(`Sources/ComposableArchitecture2/Features/DependencyKeyRewriting.swift` is entirely wrapped in
`#if Dependencies`).

**For SimpleRandom: enable `Dependencies`.** SQLiteData is built on swift-dependencies
(`@Dependency(\.defaultDatabase)`, `prepareDependencies`), so it is required regardless.

### Stability verdict

- Point-Free's own kick-off post is explicit:
  > "Remember, this is a beta, so: We don't recommend shipping things you write with it to
  > production. This is the time to find bugs, performance issues, etc. […] We *do* recommend
  > exploring patterns with toy apps!"
  > — [discussion #3], "Beta Preview Kick-off", 2026-04-02

- The README opens with a `> [!WARNING]` block: "This library is in beta preview and has not yet
  been officially released. The API is subject to change."

- There is nothing to pin to but a moving branch. **Resolve once and commit the SHA**, then bump
  deliberately, or every `swift package resolve` is an API-churn event.

- Worse, TCA26's *own* transitive dependencies are branch pins too, not versions:
  `swift-case-paths` `branch: "26"`, `swift-clocks` `branch: "clocks-2"`, `swift-navigation`
  `branch: "relax-sendable"` (`Package.swift`). Those branches move under you, and one of them
  actively conflicts with released SQLiteData — see [§6](#6-known-rough-edges-and-migration-hazards).

- Churn is not hypothetical. Between 2026-06-03 and 2026-06-05 the library introduced
  `@FeatureEnvironment` (PR #138, commit `b80a48a`) and renamed `@FeatureLocal` to `@FeatureState`
  (PR #141, commit `b9e7ff7`) — two breaking changes in three days, verified with
  `git log -S` over the full clone.

### Platform and toolchain floor

- `// swift-tools-version: 6.3` with `swiftLanguageModes: [.v6]` (`Package.swift`) — needs a
  Swift 6.3 toolchain, i.e. Xcode 26.x. Issue [#163] is filed against "Swift 6.3.2 / Xcode 26.5".
- `platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10)]` (`Package.swift`).
- **But** `StoreActor`, `TestStoreActor`, `StaticFeature`'s actor-scoping members and the internal
  `Task.immediate` paths are all `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`
  (`Sources/ComposableArchitecture2/StoreActor.swift:7,504`,
  `Testing/TestStoreActor.swift:13`, `StaticFeature.swift:22,39,73,87`, `Internal/Task.swift:10,33,53`).
  The map's iOS 26 floor is exactly what unlocks these.
- Every non-test target compiles with `ExistentialAny`, `ImmutableWeakCaptures`,
  `InferIsolatedConformances`, `InternalImportsByDefault`, `MemberImportVisibility` and
  `NonisolatedNonsendingByDefault` upcoming features enabled (`Package.swift`, trailing
  `for target in package.targets` loop). Anything you write against it inherits that strictness at
  the boundary.

---

## 2. Writing a feature from scratch: what survives, what's renamed, what's gone

The README states the intent plainly:

> "The most visible change in 2.0 is that we are moving away from 'reducer' terminology. While the
> roots of ComposableArchitecture were nourished by projects such as Redux and Elm, over time we
> have deviated so far from those ideas that it no longer feels correct to channel their
> terminology."
> — README, `TCA26@363d646`

Most 1.x vocabulary is **removed**, not renamed. Verified by grepping
`Sources/ComposableArchitecture2/` (the 2.0 module only — 1.x symbols still exist inside the
`ComposableArchitecture1` compatibility module):

| 1.x symbol | Status in ComposableArchitecture2 | Replacement |
| --- | --- | --- |
| `Reducer`, `@Reducer`, `Reduce` | **Gone** | `@Feature` / `FeatureProtocol`, and `Update` for synchronous mutation |
| `Effect`, `.run`, `.send` | **Gone** | the implicit `store` — `store.addTask { … }` |
| `@ObservableState` | **Gone** | `@Feature` applies `@ValueObservable` to `State` for you |
| `@Presents`, `PresentationAction` | **Gone** | plain `State?` + `.ifLet(\.child, action: \.child)` |
| `BindableAction`, `BindingReducer`, `@BindingState` | **Gone** | `$store.name` binds any writable state property directly |
| `ViewStore`, `WithViewStore` | **Gone** | the store *is* observable; read `store.count` in the view |
| `StackState`, `StackAction` | **Gone** | plain `[Path.State]` + `case path(Path.State.ID, Path.Action)` |
| `IdentifiedArray`, `IdentifiedAction` | **Gone** from the 2.0 surface | plain `Array` + `(State.ID, Action)` |
| `AlertState`, `ConfirmationDialogState` | **Gone** | the `Prompt` protocol |
| `@Dependency(\.dismiss)` | **Gone** | `store.dismiss()` (`FeatureDynamicProperties/FeatureStore.swift:339`) |
| `Scope` | **Survives**, unchanged shape | `Scope(\.child, action: \.child) { Child() }` |
| `Store`, `StoreOf<F>` | **Survives**, reshaped | `Sources/ComposableArchitecture2/Store.swift` |

### The shape of a feature

```swift
@Feature struct Counter {
  struct State { var count = 0 }
  enum Action {
    case decrementButtonTapped
    case incrementButtonTapped
  }
  var body: some Feature {
    Update { state, action in
      switch action {
      case .decrementButtonTapped: state.count -= 1
      case .incrementButtonTapped: state.count += 1
      }
    }
  }
}
```
(README, `TCA26@363d646`.)

Specifics that change how you write day to day, all from `TCA26@363d646`:

- **`Update` returns nothing.** "There are no return statements in `Update`." (README)
- **`State` needs no `Equatable`.** `TestStore` is built on
  [swift-debug-snapshots](https://github.com/pointfreeco/swift-debug-snapshots) and is generic over
  `Subject.State: DebugSnapshotConvertible`, which `@Feature` wires up. The README calls this out
  directly: testing works "without making your `State` `Equatable`, and you can even store reference
  types in `State` without hurting testability."
- **Async work replaces `Effect`.** Every feature body has an implicit `store`. `store.addTask { … }`
  enqueues work; inside it you can `try store.send(_:)`, `try store.modify { … }` and read state
  (`try store.remainingSeconds`). All `store.modify` mutations are "serialized on the store's actor,
  fully observable by SwiftUI, and fully visible to `TestStore`" (README).
- **`store.addTask` is `@available(*, noasync)`**
  (`FeatureDynamicProperties/FeatureStore.swift:89`) — you call it from *synchronous* update
  closures, never from inside async code.
- **Cancellation is identity-based.** `@StoreTaskID var apiRequest` (in `State` or on the feature),
  then `store.addTask(id: store.apiRequest) { … }`. A new task with the same ID cancels the previous
  one. `store.apiRequest.isRunning` is readable from the view for loading indicators.
  (`Sources/ComposableArchitecture2/StoreTaskID.swift`,
  `Examples/SwiftUICaseStudies/Asynchrony/AsynchronyStoreTaskID.swift`.)
- **Lifecycle hooks replace `onAppear` / `.task` actions**: `.onMount { state in }`,
  `.onMount(id:) { state in }` (re-fires and cancels prior work when the ID changes),
  `.onDismount { state in }`, `.onChange(of:)`
  (`Sources/ComposableArchitecture2/FeatureModifiers/{OnMount,OnDismount,OnChange}.swift`).
  README: `onMount` is "analogous to SwiftUI's `task` view modifier, except it is called only when
  the feature is created, not every time it appears on screen."
- **`@FeatureState`** is SwiftUI-`@State`-like feature-local storage that parents and tests cannot
  see (README "Better encapsulation";
  `Sources/ComposableArchitecture2/FeatureDynamicProperties/FeatureState.swift`).
  *This is the property wrapper the skill still calls `@FeatureLocal` — see [§7](#7-the-local-pfw-composable-architecture-2-skill-has-drifted).*
- **Private state is invisible to tests.** `@DebugSnapshot` skips `private` properties, so internal
  bookkeeping doesn't clutter assertions (README).
- **`Features { … }`** groups sibling features so a modifier applies to the group
  (`Sources/ComposableArchitecture2/Features/Features.swift`).
- **New composition primitives with no 1.x equivalent**, all in `Sources/ComposableArchitecture2/Features/`
  and documented under `Documentation.docc/Articles/FeatureCommunication/`:
  - `Spawn` / `.spawn(_:)` — a child with its own independent store whose actions never route through
    the parent. "Best of all, all of the communication tools still work for spawned stores: events
    bubble up, preferences aggregate, dependencies flow down, and delegate closures work." (README)
  - `FeatureEventKey` + `store.post` / `.onEvent` — one-shot child→ancestor notifications. Can be
    `private`, which lets you keep effect responses out of the public `Action` enum entirely.
  - `FeaturePreferenceKey` + `.preference` / `.onPreferenceChange` — SwiftUI-`PreferenceKey`-shaped
    upward aggregation.
  - `@Trigger` + `.onTrigger` — a parent commanding a child to do work.
  - Plain delegate closures (`let onSend: (String) throws -> Void`) replacing 1.x delegate actions.

### Store ownership in SwiftUI

`Store` is a `@MainActor final class` conforming to `Observable`, and
`Sources/ComposableArchitecture2/Store+Combine.swift` adds a `nonisolated ObservableObject`
conformance. The library's own app and case studies own stores with **`@StateObject`, created in the
view or the `App`**:

```swift
@main
struct VoiceMemosApp: App {
  @StateObject var store = Store(initialState: VoiceMemosList.State()) { VoiceMemosList() }
  var body: some Scene {
    WindowGroup { NavigationStack { VoiceMemosListView(store: store) } }
  }
}
```
(`Examples/VoiceMemos/VoiceMemosApp.swift`. Every case study, e.g.
`Examples/SwiftUICaseStudies/Composition/EnumPresentations.swift:42`, does the same in the view.)

Child views take `let store: StoreOf<Child>`, or `@Bindable var store: StoreOf<Child>` when they need
bindings — often via the in-body `@Bindable var store = store` idiom the case studies use.

---

## 3. Navigation: tabs, stacks, sheets, and SwiftNavigation

### Tabs — just `Scope` plus a binding

There is no tab-specific API. DocC files `Scope` under the heading **"Tabs and components"**
(`Documentation.docc/Articles/FeatureComposition.md`). The library's own three-tab example
(`Examples/SwiftUICaseStudies/FeatureCommunication/Preferences.swift`):

```swift
@Feature struct Preferences {
  struct State {
    var child1 = Child.State()
    var child2 = Child.State()
    var child3 = Child.State()
    var currentTab: Tab = .one
    var totalBadgeCount = 0
    enum Tab { case one, two, three }
  }
  enum Action { case child1(Child.Action); case child2(Child.Action); case child3(Child.Action) }
  var body: some Feature {
    Features {
      Scope(\.child1, action: \.child1) { Child() }
      Scope(\.child2, action: \.child2) { Child() }
      Scope(\.child3, action: \.child3) { Child() }
    }
    .onPreferenceChange(TotalBadgeCount.self) { value, state in state.totalBadgeCount = value }
  }
}

// View:
TabView(selection: $store.currentTab) {
  Tab("One", systemImage: "circle", value: .one) {
    ChildView(store: store.scope(\.child1, action: \.child1))
  }
  .badge(store.child1.badgeCount)
  …
}
```

`$store.currentTab` is a direct binding into state — no action, no `BindingReducer`. This maps
one-to-one onto SimpleRandom's Lists / Combine / Settings tabs. Badges, if they ever appear, come
from `FeaturePreferenceKey`.

### Sheets, covers and drill-downs — optional state + `ifLet` + stock SwiftUI `item:`

```swift
@Feature struct EnumPresentations {
  @Feature enum Destination {
    case drillDown(Stopwatch)
    case fullScreenCover(Stopwatch)
    case sheet(Stopwatch)
  }
  struct State { var destination: Destination.State? }
  enum Action {
    case destination(Destination.Action)
    case sheetButtonTapped
    …
  }
  var body: some Feature {
    Update { state, action in
      switch action {
      case .sheetButtonTapped: state.destination = .sheet(Stopwatch.State())
      …
      }
    }
    .ifLet(\.destination, action: \.destination) { Destination.body }
  }
}

// View:
.sheet(item: $store.scope(\.destination, action: \.destination).sheet) { stopwatchStore in … }
.fullScreenCover(item: $store.scope(\.destination, action: \.destination).fullScreenCover) { … }
.navigationDestination(item: $store.scope(\.destination, action: \.destination).drillDown) { … }
```
(`Examples/SwiftUICaseStudies/Composition/EnumPresentations.swift`, verbatim structure.)

Deltas from 1.x: no `@Presents`, no `PresentationAction` wrapper, no `\.$destination` key path, no
`sheet(store:)` overloads. You use **stock SwiftUI `item:` modifiers** against a scoped
`Binding<Store<…>?>`, with case key paths selecting the presentation style. `Destination.body`,
`Destination.State`, `Destination.Action` and `Destination.StoreEnumeration` are all synthesised by
`@Feature enum`.

**For SimpleRandom:** the randomise-result sheet on the Lists tab is exactly this shape — an optional
destination state plus `.ifLet` plus `.sheet(item:)`.

### Alerts and dialogs — the `Prompt` protocol

`AlertState` / `ConfirmationDialogState` are gone. A destination case conforms to `Prompt`, which
provides a default `body` and auto-`nil`s the destination after any action
(`Sources/ComposableArchitecture2/Features/Prompt.swift`):

```swift
@Feature enum Destination {
  case alert(Alert)
  case confirmationDialog
  @Feature struct Alert: Prompt {
    struct State { var title = ""; var message = ""; var note = "" }
    enum Action { case save; case delete }
  }
}
```
(`Examples/SwiftUICaseStudies/Composition/Prompts.swift`.) The parent never sets
`state.destination = nil` after handling a prompt action.

### Stacks — plain arrays, and the least-documented corner

```swift
@Feature enum Path {
  case basics(BasicsFeature)
  case summary(SummaryFeature)
  …
}
@Feature struct Parent {
  struct State { var path: [Path.State] = [] }
  enum Action { case path(Path.State.ID, Path.Action) }
  var body: some Feature {
    Update { state, action in … }
      .forEach(\.path, action: \.path, dismissStyle: .stack) { Path.body }
  }
}

// View:
NavigationStack(path: $store.scope(\.path, action: \.path)) {
  RootView()
    .navigationDestination(for: Parent.Path.StoreEnumeration.self) { store in
      switch store {
      case .basics(let store): BasicsStep(store: store)
      case .summary(let store): SummaryStep(store: store)
      …
      }
    }
}
```
Sources: `Examples/SwiftUICaseStudies/FeatureCommunication/FeatureBindings.swift:100,112` for the
`NavigationStack(path:)` + `navigationDestination(for: …StoreEnumeration.self)` form;
`Tests/ComposableArchitecture2Tests/OnChangeTests.swift:507`,
`ForEachFeatureTests.swift:450` and `StoreSwiftUITests.swift:40` for `dismissStyle: .stack`.

Two gotchas:

1. **`dismissStyle` defaults to `.list`, not `.stack`.** Signature:
   `forEach(_:action:dismissStyle: some ForEachDismissStyle = .list, …)`
   (`Sources/ComposableArchitecture2/Features/ForEach.swift:32,77`). `.list` removes only the
   dismissed element; `.stack` pops everything above it. The library's own stack example
   (`FeatureBindings.swift:65`) omits `dismissStyle:` and therefore gets `.list` — the library is
   inconsistent with itself here, so don't pattern-match from that file.
2. **There is no stack-navigation case study on `main`.** An unmerged `stack-navigaiton-case-study`
   branch exists (`gh api repos/pointfreeco/TCA26/branches`), and [discussion #82]
   ("Migration: Navigation Stacks") is a member asking how to do it, answered only by another member
   linking their own sample repo. This is the thinnest part of the library's documentation.

*Relevance to SimpleRandom:* the Lists tab needs a drill-down (list → its items). That is a
one-level stack; `.navigationDestination(item:)` on an optional destination
([EnumPresentations](#sheets-covers-and-drill-downs--optional-state--iflet--stock-swiftui-item)) is
the better-trodden path and probably sufficient. Reach for `[Path.State]` + `dismissStyle: .stack`
only if the drill-down grows deeper.

### Relationship to SwiftNavigation

Three facts that are easy to conflate:

1. **The `SwiftNavigation` package trait is UIKit-only.** Its DocC page describes extending
   `UIBindable` and `UIBinding` with store-scoping helpers
   (`Documentation.docc/Articles/SwiftNavigationIntegration.md`), and
   `Sources/ComposableArchitecture2/Traits/SwiftNavigation.swift` mirrors `Store+SwiftUI.swift` for
   `UIBinding`. **A SwiftUI-only app does not need this trait.**
2. **`ComposableArchitecture2` does not depend on SwiftUINavigation at all.** Only
   `ComposableArchitecture1` lists `SwiftUINavigation` / `UIKitNavigation` unconditionally
   (`Package.swift` `targets:`). TCA 2's SwiftUI support is stock SwiftUI plus
   `Bindable.scope(_:action:)` from `Store+SwiftUI.swift`.
3. **You may still want SwiftUINavigation as a direct dependency, for alerts.**
   `Examples/SwiftUICaseStudies/Composition/Prompts.swift` opens with `import SwiftUINavigation` and
   uses `.alert(item:title:actions:message:)` / `.confirmationDialog(item:…)` — those `item:`-based
   overloads come from SwiftUINavigation, not SwiftUI. If SimpleRandom wants state-driven alerts in
   that style, add `pointfreeco/swift-navigation` as a *direct* app dependency (which, note, SPM will
   resolve to TCA26's `relax-sendable` branch pin for the whole graph).

---

## 4. Composition with SQLiteData and with dependencies

### `@FetchAll` / `@FetchOne` in `Feature.State` — explicitly supported

This is a deliberate, first-class integration. `@Feature` applies the `@ValueObservable` macro to
`State`, and that macro keeps an allowlist of property wrappers that do their own observation and so
must **not** be rewritten into `ValueObservationTracked`:

```swift
let knownSupportedValueObservationPropertyWrappers: Set = [
  // TCA2
  "FeatureBinding", "FeatureState", "StoreTaskID", "Trigger",
  // Point-Free ecosystem
  "Fetch", "FetchAll", "FetchOne", "Shared", "SharedReader",
  // TCA1 upgrade compatibility
  "PresentationState", "Presents",
]
```
(`Sources/ComposableArchitecture2Macros/Internal/Extensions.swift:426–441`, `TCA26@363d646`.)

The library asserts this in its own macro snapshot test: given a `State` containing `@Shared`,
`@FetchAll` and a plain `var count = 0`, the expansion leaves the first two **byte-for-byte
untouched** while rewriting `count` into a tracked property
(`Tests/MacroTests/ValueObservableMacroTests.swift:106–160`).

So `@FetchAll var lists: [ListRecord]` inside a `@Feature`'s `State` is the supported pattern.
`@Shared` in `State` is exercised throughout TCA26's own suite (`Tests/FeatureStoreTests/`,
`Tests/SpawnTests/`).

Practical shape for SimpleRandom:

- **Reads:** `@FetchAll` / `@FetchOne` in `Feature.State`; the view reads `store.lists`.
- **Writes:** through `@Dependency(\.defaultDatabase)` declared on the `@Feature`, used inside
  `store.addTask { … }`.
- **Bootstrapping:** `prepareDependencies { $0.defaultDatabase = … }` and `SyncEngine` setup at the
  `@main` entry point, outside the feature graph. TCA-agnostic.
- **Caveat with real teeth:** with `@FetchAll`, database mutations arrive as *observation callbacks*,
  not as actions through `Update`. `TestStore` will not see them as received actions; you assert them
  with `store.expect { … }` or react with `.onChange(of:)`. [Discussion #116] ("Testing `onChange`
  with externally updated `@Shared` state") is the closest thing to guidance and remains an
  unanswered Q&A. Under iCloud `SyncEngine`, remote writes land the same way. Budget for this being
  the least-charted seam in the app.

### Dependencies: `@FeatureEnvironment` is native, `@Dependency` is the interop — and that's fine

TCA 2 ships its own SwiftUI-`@Environment`-shaped dependency system, and the DocC is unambiguous
about how the two relate:

> "The [Dependencies](https://github.com/pointfreeco/swift-dependencies) package … is an
> **alternative** to ComposableArchitecture's `EnvironmentValues`, but suited to applications that
> need to share dependencies across non-ComposableArchitecture features and paradigms."
> — `Documentation.docc/Articles/DependenciesIntegration.md`, `TCA26@363d646` (emphasis added)

The native system:

- `@FeatureEnvironment(\.someKey) var value` on a `@Feature`
  (`Sources/ComposableArchitecture2/Environment/FeatureEnvironment.swift`).
- `FeatureEnvironmentValues` with built-ins for `calendar`, clocks, `date`, `fireAndForget`,
  `notificationCenter`, `timeZone`, `uuid`
  (`Sources/ComposableArchitecture2/Environment/EnvironmentKeys/`).
- Custom keys via the `@FeatureEnvironmentEntry(liveValue:previewValue:)` macro, e.g.
  `Examples/SwiftUICaseStudies/Shared/FactClient.swift`.
- Overridden with the `.environment(\.key, value)` feature modifier, and in tests with the
  `.environment(_:_:)` suite trait from `ComposableArchitectureTestSupport` plus
  `@FeatureEnvironment(\.continuousClock, as: TestClock<Duration>.self) var clock`
  (`Examples/SwiftUICaseStudiesTests/Lifecycle/OnMountIDTests.swift:8–11`).

**Across the whole `Examples/` tree there are 23 uses of `@FeatureEnvironment` and zero uses of
`@Dependency`** (verified by grep at `TCA26@363d646`).

swift-dependencies interop exists behind the `Dependencies` trait: the `.dependency(_:)`,
`.dependency(_:_:)` and `.transformDependency(_:transform:)` feature modifiers
(`Sources/ComposableArchitecture2/Features/DependencyKeyRewriting.swift`),
`Dependencies.DateGenerator` / `UUIDGenerator` bridging into `FeatureEnvironmentValues`
(`Environment/EnvironmentKeys/{Date,UUID}.swift`), and task-local propagation of `DependencyValues`
through the feature tree (`Internal/Core.swift`).

**Recommendation for SimpleRandom.** SQLiteData *is* the "non-ComposableArchitecture paradigm" the
DocC is talking about, so this is a deliberate mix rather than a compromise:

- Enable the `Dependencies` trait and use `@Dependency(\.defaultDatabase)` for all database access.
- Use `@FeatureEnvironment` for everything the app owns — clocks, `uuid`, `date`, any client type —
  because that is the idiom the library's own code and tests are written in, and because
  `@FeatureEnvironment` overrides compose through the feature tree.
- Note that clocks in `FeatureEnvironmentValues` require the **`Clocks` trait** as well
  (`Package.swift`; `Environment/EnvironmentKeys/Clocks.swift`). Enable it if any feature needs
  time control.

---

## 5. Testing: `TestStore`, `TestStoreActor`, and exhaustivity

`TestStore` survives and exhaustive testing is still the default, but the mechanics changed
substantially. README:

> "All features built with 2.0 are still 100% testable and exhaustively testable. The `TestStore`
> will still catch you every step of the way to make sure you assert on every piece of state change,
> every effect, and every dependency."

### Two stores

- **`TestStore`** — `@MainActor final class`, for main-actor-isolated features
  (`Sources/ComposableArchitecture2/Testing/TestStore.swift`).
- **`TestStoreActor`** — `final actor`, "provides the same testing experience but runs on a
  non-global actor, maximizing parallelization of your tests" (README), and is
  `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`
  (`Testing/TestStoreActor.swift:13`). **SimpleRandom's iOS 26 floor makes this available** — prefer
  it for features that are not main-actor-isolated.

Both are constrained on `Subject.State: DebugSnapshotConvertible`, which `@Feature` supplies.

### Exhaustivity

Still on by default. `TestExhaustivity` is a **task-local**, not a dependency
(`Sources/ComposableArchitecture2/Testing/TestExhaustivity.swift`, quoted in full):

```swift
@nonexhaustive
public enum TestExhaustivity: Codable, Sendable, Hashable {
  @TaskLocal public static var current = on
  case on
  case off(showSkippedExpectations: Bool)
  public static var off: Self { .off(showSkippedExpectations: false) }
}
```

Turn it off per test with the Swift Testing trait `@Test(TestExhaustivity.$current.set(.off))`, or
scope it with `await TestExhaustivity.$current.withValue(.on) { … }`. Both forms appear throughout
`Tests/ComposableArchitecture2Tests/TestStoreTests.swift` and `TestStoreActorTests.swift`.
(**Not** `@Test(.dependency(\.exhaustivity, .off))` — see [§7](#7-the-local-pfw-composable-architecture-2-skill-has-drifted).)

### What is new in the assertion surface

From `Sources/ComposableArchitecture2/Testing/TestStore.swift`:

- **Assertion closures mutate `inout State.DebugSnapshot`, not `inout State`.** Private properties
  and `@FeatureState` are invisible to tests by construction (README, "Better encapsulation").
- `send(_:changes:)` / `receive(_:timeout:changes:)` — familiar, with trailing-closure spelling
  preserved.
- `send(_:to:)` / `receive(_:from:)` — send to and receive from **spawned** children (lines 212–330).
- `receive(key:value:)` — assert on **events** (lines 578–650).
- `trigger(…)` — fire and assert on **triggers** (lines 755–938).
- `store.modify { … } changes: { … }` — simulate a binding write or an external mutation (line 678).
- `store.expect { … }` — assert state changes that landed from in-flight async work (line 939).
  *This is the hook for `@FetchAll` / `SyncEngine` observation callbacks.*
- `await store.dismount()` — end the feature's lifetime and drain in-flight tasks (line 967). Needed
  because features now have a real lifecycle.
- `TestStoreMatcher<Value>` for matching received action payloads
  (`Testing/TestStoreMatcher.swift`).

On `TestStore` (main-actor) `send` and `modify` are synchronous and return `Task?`; `receive` and
`dismount` are `async` (`Examples/SwiftUICaseStudiesTests/Lifecycle/OnMountIDTests.swift`).

The README claims tests are "less flaky and more deterministic thanks to full control of isolation
throughout the entire stack." Note issue [#130] below, which complicates that claim on the iOS
Simulator specifically.

---

## 6. Known rough edges and migration hazards

### Blocking for this stack — issue [#169]

**TCA26's `swift-case-paths` branch pin conflicts with current StructuredQueries / SQLiteData.**
Filed 2026-07-20, still open.

TCA26 pins `swift-case-paths` to `branch: "26"` (`Package.swift`), and SPM resolves one revision of
that package for the whole dependency graph. But `swift-structured-queries` requires the
`CasePathsMacrosSupport` target `.when(traits: ["CasePaths"])`
(`swift-structured-queries/Package.swift:114–116`), and the `26` branch does not contain that target.
Verified directly:

```
swift-case-paths @ main:  CasePaths  CasePathsCore  CasePathsMacros  CasePathsMacrosSupport
swift-case-paths @ 26:    CasePaths  CasePathsMacros
```
(`gh api repos/pointfreeco/swift-case-paths/contents/Sources` vs `…?ref=26`.)

Reported error: `'CasePathsMacrosSupport' required by package 'swift-structured-queries' target
'StructuredQueriesMacros' not found in package 'swift-case-paths'`.

Point-Free's own answer, on the issue:

> "Hi @joseph-elmallah, it will take us some time to get the `26` branch of swift-case-paths merged
> with the newest stuff on main, so for now I think you will need to depend on an older version of
> StructuredQueries."
> — mbrandonw, [#169], 2026-07-21

**Mitigation — do not enable SQLiteData's `CasePaths` trait.** SQLiteData declares `CasePaths`
("Introduce support for enum tables") as an opt-in trait with no `.default(enabledTraits:)` entry,
and forwards it to StructuredQueries only `.when(traits: ["CasePaths"])`
(`sqlite-data/Package.swift`, traits block and the `swift-structured-queries` dependency). Every
`CasePathsMacrosSupport` reference in StructuredQueries is likewise trait-conditional. Leaving the
trait off costs SimpleRandom **only enum-table support**, which the Lists / Items / Settings schema
almost certainly does not need. This should be re-verified at first `swift package resolve`, before
the module graph is locked.

The reporter in [#169] also hit release-build breakage tied to
[swift-structured-queries#296](https://github.com/pointfreeco/swift-structured-queries/issues/296)
and resorted to a personal fork of the `26` branch — a signal that the pinned-branch situation is
actively painful for anyone combining TCA26 with a current SQLiteData.

### Other open issues (all confirmed open at time of writing)

| Issue | Filed | Why it matters here |
| --- | --- | --- |
| [#167] Inert store after event posting | 2026-07-04 | Store stops responding after an event is posted from a spawned child **in a sheet**. Minimal repro with a failing test. Directly in the path of "randomise sheet posts a result event". |
| [#163] `Store.deinit` crashes swift-frontend in Release | 2026-06-20 | `EarlyPerfInliner` SIL pass crash on **tvOS** Release/Archive builds, Swift 6.3.2 / Xcode 26.5. Debug unaffected. Not an iPhone blocker as reported, but it is a compiler-level fragility in `Store.deinit`. |
| [#130] `StoreTaskIDTests` fail on the iOS Simulator | 2026-05-29 | The library's own `@StoreTaskID` tests are green on macOS and **reliably red on the iOS Simulator** — state hasn't settled when asserted. Undercuts the "less flaky" claim on exactly the platform this app tests on. |
| [#127] Posting an event from `onDismount` doesn't work | 2026-05-22 | `store.post` from `.onDismount` logs "Feature store tried to post an event from a dismounted feature" and raises a runtime warning. Rules out "tell the parent I'm gone" via events — e.g. a sheet reporting its result on the way out. Post *before* dismissing instead. |

### Documentation gaps

- The DocC catalog is **substantially unwritten**. `ComposableArchitecture2.md` still contains the
  Xcode placeholder `<!--@START_MENU_TOKEN@-->Text<!--@END_MENU_TOKEN@-->`;
  `FeatureFundamentals-StoreTaskManagement.md` has four bare `TODO: todo` sections;
  `FeatureCommunication.md` has a `TODO: ?`; `FeatureFundamentals-Isolation.md` — the one genuinely
  deep article — carries `[scoped](TODO)` / `[spawned](TODO)` placeholder links.
  `SwiftUIIntegration.md`, `TestingFeatures.md` and `FeatureComposition.md` are little more than
  symbol indexes.
- `DependenciesIntegration.md` and `SwiftNavigationIntegration.md` both show an **invalid SPM
  snippet**: `.package(url: …, from: "main", traits: […])`. `from:` takes a version, not a branch.
  Use `branch: "main"`.
- No stack-navigation case study on `main` (see [§3](#stacks--plain-arrays-and-the-least-documented-corner)).
- The README is the single best document in the repo; `Examples/SwiftUICaseStudies/` is the best
  reference for idiom. Read those, not DocC.

### Behavioural traps worth internalising

- **`store.addTask` is `@available(*, noasync)`** — enqueue from synchronous update closures only.
- **Task enqueueing is not immediate.** Within an `Update`, work added by `store.addTask` starts
  only after the current action finishes routing; but by the time `store.send(_:)` returns to the
  caller, the effect's synchronous prefix has run, because `addTask` uses `Task.immediate`
  (`Documentation.docc/Articles/FeatureFundamentals/FeatureFundamentals-Isolation.md`, "Task
  enqueueing"; `Internal/Task.swift`).
- **Events and triggers can only be posted/invoked from inside `store.addTask`**, and their listener
  mutations apply synchronously before `post` / the trigger call returns
  (`FeatureFundamentals-Isolation.md`).
- **`forEach`'s `dismissStyle` defaults to `.list`** — pass `.stack` for navigation stacks.
- **`store.send` no longer takes an animation.** [Discussion #21] "Removal of animation from
  `store.send` intentional?" — the case studies wrap sends in
  `withAnimation { _ = store.send(.save) }` (`Examples/SwiftUICaseStudies/Composition/Prompts.swift`).
- **`@Feature enum` synthesises a lot**: `Path.body`, `Path.State`, `Path.Action`,
  `Path.StoreEnumeration`, `Path.StoreActorEnumeration` and `switch(store:)`.

---

## 7. The local `pfw-composable-architecture-2` skill has drifted

The skill at `~/.claude-personal/skills/pfw-composable-architecture-2/` is **behind `main` by roughly
two months, in both files it ships.** This is the most important operational finding in this
document, because every future implementation session will load that skill by default.

**The bundled `.swiftinterface` is stale too.** It contains `@propertyWrapper public struct
FeatureLocal<Value>` (line 151) and **zero** occurrences of `FeatureEnvironment`. On `main`,
`FeatureLocal` does not exist anywhere in the repo, `FeatureState` is the property wrapper, and
`FeatureEnvironment` is the primary dependency mechanism. Dating this from the full git history:
`@FeatureEnvironment` landed in PR #138 (`b80a48a`, 2026-06-03) and `@FeatureLocal` → `@FeatureState`
in PR #141 (`b9e7ff7`, 2026-06-05). **The shipped interface therefore predates 2026-06-03.**

*(Note: `FeatureState` does appear in the stale interface — but as a marker **protocol** for feature
state types, unrelated to the property wrapper of the same name on `main`. Grepping the interface for
`FeatureState` and concluding it is current is a trap.)*

Confirmed divergences — **trust the repo, not the skill**:

| `SKILL.md` says | `TCA26@363d646` actually has |
| --- | --- |
| `@FeatureLocal var totalTaps = 0` | `@FeatureState` (zero occurrences of `FeatureLocal` anywhere in the repo) |
| `@Dependency(\.date.now) var now` on a `@Feature`; "DO declare the `@Dependency` directly inside the `@Feature`" | `@FeatureEnvironment(\.date.now) var now`. 23 `@FeatureEnvironment` uses in `Examples/`, zero `@Dependency` |
| Dependency overrides via `withDependencies { … }` in tests | Suite trait `.environment(\.continuousClock, .test)` from `ComposableArchitectureTestSupport` |
| `@Test(.dependency(\.exhaustivity, .off))` | `@Test(TestExhaustivity.$current.set(.off))` — exhaustivity is a `@TaskLocal`, not a dependency |
| `.onChange(of: store.count) { oldCount, state in }` (2 params) | Two overloads only: `(oldValue, newValue, state)` and `(state)`. **No 2-parameter form exists** (`FeatureModifiers/OnChange.swift:13–19, 32–38`; `Examples/…/FeatureEnvironment/DynamicDependencies.swift:22`) |
| "Use `static let` to hold onto the root-most store" | `@StateObject var store = Store(…)` in the `App` (`Examples/VoiceMemos/VoiceMemosApp.swift`) |
| "DO NOT create stores in the view, including a view's initializer" | Every case study does `@StateObject var store = Store(…) { … }` **in the view** |
| `@Dependency(\.dismiss) var dismiss` for child dismissal | `store.dismiss()` on the implicit feature store (`FeatureDynamicProperties/FeatureStore.swift:339`); no dependency declaration |
| "References `references/sqlite-data.md`" | That file does not exist in the installed skill — only `SKILL.md`, `LICENSE` and `references/interface/` |
| Bundled `.swiftinterface` presented as the API reference | Predates 2026-06-03; missing `FeatureEnvironment` entirely, still has `FeatureLocal` |

Point-Free are aware the skills are new and evolving — stephencelis in [discussion #112]: "We have
some TCA2 skills in progress right now and hope to make them public in the Point-Free Way soon!"
Community practice in that thread is explicitly to read `Examples/SwiftUICaseStudies/` from the SPM
checkout before improvising a pattern. **SimpleRandom should do the same**: point sessions at the
resolved `TCA26` checkout under DerivedData `SourcePackages/checkouts/TCA26`, and treat the skill as
a starting sketch.

---

## 8. Bottom line for SimpleRandom

1. **Depend on it as** `.package(url: "https://github.com/pointfreeco/TCA26", branch: "main", traits: ["Clocks", "Dependencies"])`,
   product `ComposableArchitecture2`, then **commit the resolved SHA** and bump deliberately. Drop
   `Clocks` if no feature needs time control.
2. **Skip the `SwiftNavigation` trait** (UIKit-only). Consider a *direct* `swift-navigation`
   dependency if you want SwiftUINavigation's `.alert(item:)` style.
3. **Do not enable SQLiteData's `CasePaths` trait** until [#169] is fixed. Cost: enum tables only.
   Re-verify at first resolve.
4. **Toolchain:** Swift 6.3 / Xcode 26.x, Swift 6 language mode. The settled iOS 26 floor is what
   unlocks `StoreActor` and `TestStoreActor`.
5. **Three tabs = three `Scope`s inside `Features { }`** on a root feature plus
   `TabView(selection: $store.currentTab)`. No tab-specific API exists or is needed.
6. **The randomise sheet** is an optional `Destination` state + `.ifLet` + stock `.sheet(item:)` on a
   scoped binding. The Lists drill-down is best served by `.navigationDestination(item:)` rather than
   a `[Path.State]` stack, unless it deepens.
7. **SQLiteData fits cleanly by design** — `@FetchAll` / `@FetchOne` / `@Shared` are allowlisted in
   the `@ValueObservable` macro and asserted in the library's own snapshot tests. Writes via
   `@Dependency(\.defaultDatabase)` inside `store.addTask`; `prepareDependencies` + `SyncEngine` at
   app launch. The open question is **testing observation-driven state**, where the library has no
   documented answer ([discussion #116]) — `store.expect { … }` is the tool.
8. **`@FeatureEnvironment` for app-owned dependencies, `@Dependency` for SQLiteData.** The DocC
   explicitly frames swift-dependencies as the option for sharing across non-TCA paradigms, which is
   exactly SQLiteData's position.
9. **Point-Free explicitly say not to ship this to production.** For a deliberate showcase app that
   is an accepted trade — but budget for API churn (two breaking renames in three days in June), a
   largely unwritten DocC catalog, an undocumented stack-navigation story, four open issues, and a
   local skill that is two months stale.

[#127]: https://github.com/pointfreeco/TCA26/issues/127
[#130]: https://github.com/pointfreeco/TCA26/issues/130
[#163]: https://github.com/pointfreeco/TCA26/issues/163
[#167]: https://github.com/pointfreeco/TCA26/issues/167
[#169]: https://github.com/pointfreeco/TCA26/issues/169
[discussion #3]: https://github.com/pointfreeco/TCA26/discussions/3
[discussion #21]: https://github.com/pointfreeco/TCA26/discussions/21
[discussion #82]: https://github.com/pointfreeco/TCA26/discussions/82
[discussion #112]: https://github.com/pointfreeco/TCA26/discussions/112
[Discussion #116]: https://github.com/pointfreeco/TCA26/discussions/116
