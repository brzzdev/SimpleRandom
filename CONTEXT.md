# SimpleRandom

An iPhone app for picking one thing at random out of a list you made.

Three tabs:

- **Lists** — create Lists, add/edit/delete their Items, and randomise within one List.
- **Combine** — create Combos, each a saved set of Lists, and randomise across their pooled Items.
- **Settings** — licences and credits.

## Domain model

### Ubiquitous language

A **List** has **Items**. These are the words used in conversation, in this document, in the UI, and in Swift.

A **Combo** is a saved set of Lists, and the unit a pooled randomise runs over. You *combine* Lists into a Combo — hence the Combine tab, which holds Combos the way the Lists tab holds Lists.

A List or a Combo is either plain or a **Deck**. A Deck deals each Item at most once; when the last one has gone it is **exhausted**, and **Reshuffle** puts them all back. These four words travel together — reshuffle and exhausted both presuppose a deck.

`List` collides with SwiftUI's `List`. The domain word wins: the model type is `List`, and feature views that import SwiftUI qualify it as `Models.List`. The alternative — a second vocabulary for the code — was rejected as a permanent translation cost paid to avoid an occasional qualification.

### List

A named collection of Items, and the unit a randomise runs over.

| Field       | Type      | Notes                                    |
| ----------- | --------- | ---------------------------------------- |
| `id`        | `UUID`      | Primary key                              |
| `createdAt` | `Date`      | Sort key                                 |
| `deletedAt` | `Date?`     | **Reserved, unread in v1** — see below   |
| `drawMode`  | `DrawMode`  | `.independent` (default) or `.deck`      |
| `emoji`     | `String?`   | Optional, one grapheme cluster           |
| `name`      | `String`    | Trimmed, non-empty                       |
| `position`  | `Int?`      | **Reserved, unread in v1** — see below   |
| `updatedAt` | `Date?`     | **Reserved, unread in v1** — see below   |

### Item

A single candidate within a List. Text and nothing else: the app's job is picking one at random, and every additional field is something to design, sync, and render on the result sheet.

| Field       | Type     | Notes                                  |
| ----------- | -------- | -------------------------------------- |
| `id`        | `UUID`   | Primary key                            |
| `createdAt` | `Date`   | Sort key                               |
| `deletedAt` | `Date?`  | **Reserved, unread in v1** — see below |
| `listID`    | `UUID`   | Foreign key to `List`, `ON DELETE CASCADE` |
| `position`  | `Int?`   | **Reserved, unread in v1** — see below |
| `title`     | `String` | Trimmed, non-empty                     |
| `updatedAt` | `Date?`  | **Reserved, unread in v1** — see below |
| `weight`    | `Int?`   | **Reserved, unread in v1** — see below |

### ListDraw

One row per Item its List has dealt. The row's existence *is* the draw — see **Drawing**.

| Field       | Type    | Notes                                                    |
| ----------- | ------- | -------------------------------------------------------- |
| `itemID`    | `UUID`  | Primary key **and** foreign key to `Item`, `ON DELETE CASCADE` |
| `createdAt` | `Date`  | When the Item was dealt                                   |
| `position`  | `Int?`  | **Reserved, unread in v1** — see below                    |
| `updatedAt` | `Date?` | **Reserved, unread in v1** — see below                    |

An Item belongs to exactly one List, so the Item's own id identifies the draw and no separate `id` or `listID` is needed. Foreign-key-as-primary-key is also the shape a `privateTables` side table must take — see **Sync**.

### Combo

A named set of Lists whose Items are pooled and drawn from together. A Combo references its member Lists by id rather than copying them, so it stays live as those Lists gain, lose and rename their Items.

| Field       | Type       | Notes                                  |
| ----------- | ---------- | -------------------------------------- |
| `id`        | `UUID`     | Primary key                            |
| `createdAt` | `Date`     | Sort key                               |
| `deletedAt` | `Date?`    | **Reserved, unread in v1** — see below |
| `drawMode`  | `DrawMode` | `.independent` (default) or `.deck`    |
| `emoji`     | `String?`  | Optional, one grapheme cluster         |
| `name`      | `String`   | Trimmed, non-empty                     |
| `position`  | `Int?`     | **Reserved, unread in v1** — see below |
| `updatedAt` | `Date?`    | **Reserved, unread in v1** — see below |

Deliberately the same shape as `List`, reserved columns included: one vocabulary covers both tabs.

### ComboList

One row per membership — a List belonging to a Combo.

| Field       | Type    | Notes                                       |
| ----------- | ------- | ------------------------------------------- |
| `id`        | `UUID`  | Primary key                                 |
| `comboID`   | `UUID`  | Foreign key to `Combo`, `ON DELETE CASCADE` |
| `createdAt` | `Date`  | Sort key                                    |
| `deletedAt` | `Date?` | **Reserved, unread in v1** — see below      |
| `listID`    | `UUID`  | Foreign key to `List`, `ON DELETE CASCADE`  |
| `position`  | `Int?`  | **Reserved, unread in v1** — see below      |
| `updatedAt` | `Date?` | **Reserved, unread in v1** — see below      |

### ComboDraw

One row per Item a Combo has dealt. The row's existence *is* the draw — see **Drawing**.

| Field       | Type    | Notes                                       |
| ----------- | ------- | ------------------------------------------- |
| `id`        | `UUID`  | Primary key                                 |
| `comboID`   | `UUID`  | Foreign key to `Combo`, `ON DELETE CASCADE` |
| `createdAt` | `Date`  | When the Item was dealt                     |
| `itemID`    | `UUID`  | Foreign key to `Item`, `ON DELETE CASCADE`  |
| `position`  | `Int?`  | **Reserved, unread in v1** — see below      |
| `updatedAt` | `Date?` | **Reserved, unread in v1** — see below      |

A Combo's deck state needs both ids, because an Item can belong to many Combos — unlike `ListDraw`, where the Item's id alone is enough.

### Rules

**Ownership.** An Item belongs to exactly one List. Deleting a List deletes its Items. The same text appearing in two Lists is two rows, which costs nothing — the Combine tab pools across Lists anyway.

**No nesting.** A List cannot contain a List. The sync layer rejects reference cycles between tables, so this is structural rather than a product choice. A Combo *does* hold Lists, but as a separate table pointing at them: the graph is `Combo ──< ComboList >── List ──< Item` plus `Combo ──< ComboDraw >── Item`, which is acyclic and therefore allowed. This is why combining is its own entity rather than a mode of `List`.

**Combining.** A Combo's pool is every Item of every member List, flattened. Membership is deduplicated by `listID` when the pool is built: no `UNIQUE` is available outside the primary key, so two devices adding the same List offline can produce duplicate `ComboList` rows, and left alone that would silently double the List's weight. Duplicate *Items* are not deduplicated — the same text in two member Lists is two entries and two chances, exactly as within one List.

Membership is a join table rather than a `[UUID]` column on `Combo` because conflict resolution is field-wise last-writer-wins: with an array, two devices each adding a different List offline means one edit is silently lost, whereas rows merge. Deleting a List also cascades its memberships away for free, instead of leaving a dangling id to filter at read time forever. The Combo then silently shrinks; nothing warns first.

**Ordering.** Lists, Items and Combos all sort by `(createdAt, id)` ascending — insertion order, newest last. There is no reorder gesture in v1. Order carries no meaning for a randomiser; it exists so a thing stays where the user put it.

The `id` tie-break is what makes the order the *same* order on every device. `createdAt` alone is not a total order — two devices creating rows offline in the same second leave SQLite to break the tie however it likes, and two iPhones then render the same data differently. Breaking on the primary key is arbitrary but identical everywhere, which is strictly better. It does not fix clock skew: a device running two minutes behind sorts its rows earlier than rows created later elsewhere. Nothing short of a logical clock would, and for a randomiser the cost of being a couple of positions out is nil.

**Uniqueness.** None. Two Items in a List may have identical titles, and two Lists — or two Combos — may share a name. This is deliberate: under uniform selection, adding "Pizza" twice doubles its odds, so repetition is the user's own weighting mechanism. It is also the only enforceable answer — the sync layer permits no `UNIQUE` constraint outside the primary key, so a uniqueness rule could not survive two devices editing offline.

**Selection.** Uniform across the Items in scope — the Items of one List, or the pooled Items of a Combo. Every Item in the pool has equal probability, so a 100-item List dominates a 3-item one in a Combo they share. Picking a member List first and then an Item within it was rejected: it is a second selection concept, and it breaks the rule that adding "Pizza" twice doubles its odds. `weight` is present in the schema and read by nothing.

**Drawing.** A plain List (`drawMode == .independent`) draws uniformly over all its Items on every tap, with no memory: the same Item twice in a row is legal and is not suppressed. A **Deck** (`drawMode == .deck`) draws only over Items with no `ListDraw` row, inserting one for the Item it deals; when none are left the Deck is **exhausted** and offers **Reshuffle**, which deletes every `ListDraw` row belonging to the List's Items. Reshuffle is available at any time, not only at exhaustion.

A Combo draws the same two ways, over its pool, but keeps its own deck state: a plain Combo pools everything on every tap, and a Combo Deck draws only over pooled Items with no `ComboDraw` row, inserting one for the Item it deals. It is **exhausted** when its row count equals its pool size, and **Reshuffle** deletes that Combo's rows.

Both decks are therefore the same mechanism — a row per dealt Item, whose existence is the draw, deleted by Reshuffle. Deck state was deliberately not modelled as a `drawnAt` column on `Item`: a Combo's could never live there anyway, one mechanism is easier to reason about than two, and a per-Item column on a shared record would foreclose collaboration — see **Sync**.

**Decks are independent per surface.** A Combo's draw is governed only by its own `drawMode` and its own `ComboDraw` rows. Member Lists' `drawMode` and `ListDraw` rows are neither read nor written — a Combo always pools every Item of every member List, including ones already dealt within their own List, and drawing from a Combo never writes a `ListDraw` row. "Dealt in Movies" and "dealt in Friday night" are separate facts. Nesting the two deck states was rejected: they compose into behaviour that is hard to predict, and an exhausted member List would silently shrink the pool with nowhere sensible to put its Reshuffle.

A draw row is keyed on the Item's identity and nothing else touches it. A new Item arrives undealt, so adding one to an exhausted Deck un-exhausts it. Editing an Item's title does not delete its draw row — identity is the row, not the text. Switching a Deck back to plain preserves the rows, so switching back resumes where it left off. Nothing resets a Deck on launch or on a timer.

Randomness comes from `@Dependency(\.withRandomNumberGenerator)`; the selection, exhaustion and reshuffle logic itself lives in the reducer rather than behind a client, so tests seed the generator and assert real draws.

**A draw row is written when the result is shown, not when it is computed.** In v1 those are the same instant, so this constrains nothing. It matters the moment anything sits between the two — a v2 reveal animation decides the winner at the tap, and if the row is written there, dragging the sheet away mid-animation spends a card the user never saw, with no history to say which one. A Deck may not deal behind the user's back.

**Draw results are not persisted.** There is no last-result memory and no draw history table; `Item.drawnAt` and a `ComboDraw` row are the only records that a draw happened. A Combo's result names the Item's source List alongside the title — load-bearing precisely because duplicate Items are not deduplicated, so "Pizza" from Lunch and "Pizza" from Dinner would otherwise be indistinguishable.

**Bounds.** No maximum, and no minimum. An empty List is legal — you have just made it — and its Randomise button is visible but disabled, with a prompt to add something. A one-item List randomises normally and always returns that item — and as a Deck, exhausts after a single draw.

The same holds for a Combo: zero member Lists is legal, with Randomise disabled and a prompt to add one; one member List is legal and behaves like that List; and members that are all empty leave an empty pool, which disables Randomise too. There is no "combining needs two Lists" rule — it would block building a Combo up one List at a time.

### Reserved columns

The CloudKit schema is append-only from the first shipped build: columns can never be renamed, moved, or dropped. `deletedAt`, `position`, `updatedAt`, and `weight` are therefore written into v1's schema and read by nothing, because reserving them is free now and impossible later. This applies to every table, join tables included — `ComboList.position` is what a future "reorder a Combo's Lists" would want.

`position` is the most likely v1.x request (drag to reorder). `deletedAt` is the next most likely: v1 deletes are hard and unrecoverable (see **Sync**), and undo is the obvious thing to be asked for afterwards. It is reserved on `List`, `Item`, `Combo` and `ComboList` — everything whose removal is a user gesture — and deliberately **not** on `ListDraw` or `ComboDraw`, where the only deletion is Reshuffle. Reshuffle is designed as a hard delete, and a `deletedAt` there would quietly break the arithmetic that decides whether a Deck is exhausted.

A reserved column that nothing has ever written is also free to *relocate* later, because there is no data to migrate — only a dead column left behind, which the append-only rule permits. That is why `position` can stay on the record despite a future `CKShare` wanting it in a side table, and why deck state could not.

## Sync

**SimpleRandom works fully without iCloud; with iCloud it quietly keeps one person's iPhones in step, and it never claims more than it can know.**

**Local-only is a supported state, not a degraded one.** There is no sign-in prompt, no nag and no gate — every write goes to local SQLite first, so an app with no iCloud account is an ordinary working app whose changes never leave the device. The `Sync` row in Settings is the only place the app mentions it.

**Signing out of iCloud does not delete anything.** `SyncEngine` wipes local data on an account change by default; a `SyncEngineDelegate` overrides that. On `.signOut` the rows stay — signing out is simply the transition into local-only operation, and an app that never required an account should not punish leaving one. On `.switchAccounts` the local data *is* deleted, because those rows belong to the previous account. No alert is raised either way: an account change can arrive while the app is not running, so the prompt would land out of context, and it would ask a question with only one safe answer. `Delete All Lists` in Settings remains the deliberate way to get rid of everything.

**Deletes are hard, immediate and global.** A delete on one iPhone really removes the row on the other; there is no trash and no undo. Deleting a List cascades its Items and its Combo memberships, so a Combo silently shrinks. The outcome of a delete on one device racing an edit on another is undocumented by the sync layer and is accepted as unspecified — the blast radius is one row of text.

**Everything in the domain model syncs, deck state included.** Dealing an Item on one iPhone leaves it dealt on the other, and Reshuffle puts the cards back everywhere. A Deck is a stateful object, not a view preference. Only the `Theme` preference is device-local, held in `@Shared(.appStorage)`.

**Conflicts merge field by field, last writer wins.** This is the sync layer's only strategy and is not customisable. It suits names and titles well; it is why no `UNIQUE` constraint exists, why membership is a join table rather than an array column, and why nothing in the schema is counter-shaped.

**The app is silent about sync failures.** Network, quota and service errors are swallowed and retried by the sync layer, which exposes no error to bind a UI to; inventing one would mean guessing, and a false "Couldn't sync" is worse than silence. `View Logs` in Settings — which ships in release builds for exactly this reason — is the whole diagnostic surface. App-side database writes are wrapped in `withErrorReporting` so local failures are logged too.

**First launch on a new device shows that it is checking.** There is no initial-sync-complete signal in the sync layer's API, so an empty Lists tab otherwise means both "no lists yet" and "your lists have not arrived". A device-local, one-way `hasCompletedFirstFetch` flag is set once the first fetch returns; until then, and only when an iCloud account is available, the Lists and Combine tabs say they are checking iCloud rather than that they are empty. Without it a user recreates lists that already exist, and the duplicates sync back.

**Pull to refresh** on the Lists and Combine tabs triggers a fetch. It means "check for changes from my other devices" — local changes are already queued and sending on their own — and it promises nothing about having finished. It is the only user-accessible remedy in an app that has otherwise decided to stay quiet.

**No per-record sync state.** The sync layer's metadata database is not attached, so there is no per-row "not yet synced" badge. That would explain sync at a granularity the rest of these decisions deliberately avoid.

### Collaboration readiness

Sharing Lists with other iCloud users (`CKShare`) is **out of scope** — sync means one person's own devices. The schema nonetheless avoids foreclosing it, because it is append-only:

- `List` has no foreign keys, so it is a valid share **root**. `Item` has exactly one foreign key pointing at it, so it would be shared along with it. The hierarchy that would actually be shared is already the right shape.
- `Combo`, `ComboList` and `ComboDraw` could never be shared — records with multiple foreign keys are excluded by the sync layer, without workaround. This is accepted: a Combo is a personal arrangement of your own Lists, not a thing to hand to someone else.
- **`ListDraw` is declared a private table from day one.** Private tables still sync across one person's devices, so this changes nothing in v1 — but it means a shared List would not carry one participant's draws into another's deck. Deck state is written on every tap, so relocating it after ship would be a live data migration under a shared schema rather than the dead column a never-written reserved column leaves behind.

## Architecture

A Tuist `Project.swift` generating a thin `SimpleRandom` app target (`dev.brzz.SimpleRandom`, `destinations: [.iPhone]`, `IPHONEOS_DEPLOYMENT_TARGET` 26.0, `SWIFT_VERSION` 6.0) whose sources are `AppHost/**` and whose only dependency is the local package's `App` product.

### Targets

`Package.swift` is `swift-tools-version:6.3`, `defaultLocalization: "en"`, `platforms: [.iOS(.v26)]`, one library product — `App`.

| Target | Depends on | Holds |
| --- | --- | --- |
| `Models` | SQLiteData | The `@Table` types — `List`, `Item`, `ListDraw`, `Combo`, `ComboList`, `ComboDraw` — plus `DrawMode`, `DrawScope` and `Theme` |
| `Database` | `Models`, SQLiteData | `migrator`, `appDatabase()`, `inMemory()`, the `SyncEngine` factory and its `SyncEngineDelegate` |
| `Preferences` | `Models` | The two `@Shared(.appStorage)` keys: `theme` and `hasCompletedFirstFetch` |
| `Acknowledgements` | ComposableArchitecture2 | `Licenses.generated.swift`, the licence list and the licence detail screen |
| `Components` | `Models`, ComposableArchitecture2 | The three views both tabs render — `EmojiField`, the index row, the pinned Randomise bar |
| `RandomiseFeature` | `Database`, `Models`, ComposableArchitecture2 | The randomise sheet and the whole draw |
| `ListDetailFeature` | `Components`, `Database`, `Models`, `RandomiseFeature`, ComposableArchitecture2 | `ListDetail` — one List's Items, its editor sheets and its pinned Randomise |
| `ListsFeature` | `Components`, `Database`, `ListDetailFeature`, `Models`, `Preferences`, `RandomiseFeature`, ComposableArchitecture2 | The Lists index |
| `CombineFeature` | `Components`, `Database`, `ListDetailFeature`, `Models`, `Preferences`, `RandomiseFeature`, ComposableArchitecture2 | The Combine index and `ComboDetail` |
| `SettingsFeature` | `Acknowledgements`, `BrzzUtils`, `Database`, `Models`, `Preferences`, ComposableArchitecture2 | The Settings form and `Logs/` |
| `AppFeature` | `CombineFeature`, `ListsFeature`, `SettingsFeature`, ComposableArchitecture2 | The root `@Feature` and the `TabView` |
| `App` | `AppFeature`, `Database`, `Preferences`, ComposableArchitecture2 | `SimpleRandomApp`, `prepareDependencies` at launch, store creation, `preferredColorScheme` |

Twelve targets. `ListDetailFeature` is extracted for the same reason `RandomiseFeature` is: both tabs present it. A Combo's member row pushes the *real* List detail, not a copy or a read-only preview, so the screen cannot live inside `ListsFeature` without `CombineFeature` importing the whole Lists index to reach it. The two tabs stay peers, neither depending on the other.

`Components` exists for the same peer problem at view scale. `EmojiField` is rendered by the List editor and the Combo form, the index row by both indexes, and the pinned Randomise bar by `ListDetail` and `ComboDetail` — and each carries accessibility treatment (see **Accessibility**) too fiddly to survive being written twice. `ListDetailFeature` is the only target both tabs already reach, and an *index* row does not belong in a *detail* target. It holds views and no logic, so it carries no tests.

Four test targets, chosen by risk rather than by symmetry: `DatabaseTests`, `RandomiseFeatureTests`, `ListsFeatureTests` and `CombineFeatureTests`. `Models`, `Preferences`, `Acknowledgements`, `Components`, `ListDetailFeature`, `SettingsFeature`, `AppFeature` and `App` carry no tests — `Delete All Lists` is covered as a cascade case in `DatabaseTests`, and `ListDetail`'s behaviour is exercised through `ListsFeatureTests`. `CombineFeature` does not depend on `ListsFeature`: its List checklist reads `Models.List` through its own `@FetchAll`.

Package dependencies are `BrzzUtils` (`branch: "tca26"`), `TCA26` (`branch: "main"`, `traits: ["Dependencies"]`), `sqlite-data` and `swift-dependencies`. Every target gets the house upcoming-feature set — `ExistentialAny`, `ImmutableWeakCaptures`, `InferIsolatedConformances`, `InternalImportsByDefault`, `MemberImportVisibility`, `NonisolatedNonsendingByDefault` — applied by a loop at the foot of the manifest, with `.treatAllWarnings(as: .error)` behind `#if compiler(>=6.4)`. `InternalImportsByDefault` means every import carries an explicit `public` or `internal`.

### Composition

Features are `@Feature` types with `@ValueObservable` state; the 1.x vocabulary (`Reducer`, `Effect`, `@Presents`, `ViewStore`, `StackState`) does not exist in this library.

`AppFeature.State` holds `var currentTab: Tab = .lists` as plain state — the app always opens on Lists — alongside the three tab features, scoped in `Features { }` under `TabView(selection: $store.currentTab)`.

`ListsFeature.State` holds `@FetchAll var lists` and `var detail: ListDetail.State?`, wired with `.ifLet` and pushed with `.navigationDestination(item:)`; `ListDetail.State` holds `@FetchAll var items` and `var randomise: RandomiseFeature.State?`, presented with `.sheet(item:)`. The push and the sheet are therefore the same idiom — optional child state — rather than a `[Path.State]` stack.

Combine is one level deeper: `CombineFeature.State` → `ComboDetail.State` → `ListDetail.State`, because a Combo's member row pushes that member's List detail. Optional child state still carries it — the third level is another `.navigationDestination(item:)` off `ComboDetail` — so the idiom is unchanged and no `[Path.State]` stack is introduced.

**`ListDetail` behaves identically wherever it is pushed.** Presented from a Combo it keeps its pinned Randomise button, its own editor sheets and its own `ListDraw` deck; nothing about it is conditional on the presenting tab. Drawing there draws from that List alone and leaves the Combo's `ComboDraw` rows untouched, which is exactly what **Decks are independent per surface** already says. The alternative — a flag suppressing the button when presented from Combine — was rejected as conditional behaviour on a shared screen to prevent something the domain model has already declared legal.

`RandomiseFeature` owns the draw, not just its presentation. Its state carries a `DrawScope` — `.list(List.ID)` or `.combo(Combo.ID)` — and the feature picks, writes the `ListDraw` or `ComboDraw` row, detects exhaustion and reshuffles.

**The pool lives in `RandomiseFeature.State`**, as a `@FetchAll` whose query is built from the `DrawScope`, rather than being assembled inside the reducer at draw time and discarded. This is only **Seams**' read rule applied — but it is also what keeps the sheet's view holding every candidate, not just the winner, which is what any later animation over the pool would need. It is not free: in Deck mode the remaining pool shrinks on every draw, so `RandomiseFeatureTests`' exhaustive assertions carry that churn alongside the result.

Its state also carries `drawToken`, an `Int` incremented on every draw and rendered by nothing. A re-roll that lands on the Item already shown changes no other state, so it is the only value the sheet's haptic and its VoiceOver announcement can trigger on — see **Accessibility**. It is not persisted; **Draw results are not persisted** is unchanged. Re-roll and Reshuffle are both buttons on the sheet, so the logic lives where the gestures land, and one test suite covers both tabs' deck arithmetic. Only the detail screens present it: you open a List, then randomise it.

### Seams

- **Reads** are `@FetchAll` / `@FetchOne` declared in `Feature.State`, which the `@ValueObservable` macro allowlists by design. There is no repository client: a client returns snapshots rather than live updates, and `Database.inMemory()` gives each test a real database built by the real `migrator`, so a hand-written mock would only add drift. (`SQLiteDataTestSupport` ships `assertQuery` and nothing else; it does not provide databases.)
- **Writes** are `@Dependency(\.defaultDatabase)` inside `store.addTask`, wrapped in `withErrorReporting`.
- **Randomness** is `@Dependency(\.withRandomNumberGenerator)`.
- **Primary keys** are a custom SQLite function registered on the connection and used as each table's column default — `appDatabase()` registers a UUIDv7 generator, `inMemory()` a counting variant. No insert site mentions an id, so none can forget one, and UUIDv7's time-ordering makes the `id` tie-break in **Sync**'s sort order agree with creation order rather than arbitrarily.
- **`createdAt`** is `@Dependency(\.date)`.
- **The account-change policy** is a pure `shouldDeleteLocalData(on: CKSyncEngine.Event.AccountChange.ChangeType) -> Bool` in `Database`, with `SyncEngineDelegate`'s method reduced to a single call to it. The delegate method takes a live `SyncEngine`, so it cannot be invoked without a CloudKit container — and the library's default implementation wipes on `.signOut`, which **Sync** rules out. The policy is extracted so that the one silent, data-destroying default in the app is testable.
- **Everything else the app owns** is `@FeatureEnvironment`, the library's native mechanism. `@Dependency` is reserved for what crosses into SQLiteData, which is what swift-dependencies is for.

The `Dependencies` trait on TCA26 is what makes this work: without it the store never re-establishes `DependencyValues` around feature work, and overrides set at store creation silently do not apply.

## Accessibility

**VoiceOver and Dynamic Type are v1 requirements, screen by screen.** The app is stock SwiftUI, so most of it works untouched; what follows is the part that does not.

Stated non-goals for v1: Switch Control, Voice Control and Full Keyboard Access tuning beyond what standard controls give; VoiceOver rotor customisation; audio graphs. Reduce Motion needs nothing — v1 ships no animation. Differentiate Without Colour needs nothing — a dealt Item is secondary text *and* a checkmark, never colour alone.

### The re-roll announcement

Nothing in SwiftUI announces changed `Text` inside a presented sheet, so **Again** is silent to VoiceOver — worse than the sighted case, which at least gets the haptic. Every re-roll therefore posts an `AccessibilityNotification.Announcement` at `.high` priority, from the view, on `drawToken` changing — the same trigger as the haptic, because they are two channels acknowledging one event. Routing it through the reducer was rejected: an announcement is a UI-layer acknowledgement, and `RandomiseFeatureTests` should not carry a seam that only ever tests its own mock.

The token's initial value is what makes this fire **on re-roll only**: the sheet's presentation already reads the opening result, and announcing there talks over it.

Both channels fire when the result **becomes visible**, which in v1 is when it is drawn. The token is named for the draw because that is the domain's word — Decks deal, `ListDraw` and `ComboDraw` record it — but the contract is the reveal. An acknowledgement that arrives before the thing it acknowledges is worse than none, so anything that later separates the two moments moves the increment, rather than leaving it where the name suggests.

What it says, in the fewest words that stay unambiguous:

| Case | Announcement |
| --- | --- |
| Lists path | `Pizza` |
| Combine path | `Pizza, from Lunch` |
| Re-rolling into an exhausted Deck | `That's the whole deck` |

Provenance is in the Combine announcement because **Draw results are not persisted** makes it load-bearing — two "Pizza"s are otherwise indistinguishable — and on re-roll the announcement is the only channel carrying it. The source List's emoji is *excluded*: VoiceOver reads it by its CLDR name, so including it puts "sandwich" in front of the only word that disambiguates. The exhausted case announces because the result element it replaces has ceased to exist, leaving focus wherever the system puts it.

**This makes the VoiceOver path better served than the sighted path**, where a repeat draw with system haptics off is still indistinguishable from a dead button. That asymmetry is accepted, not overlooked: an announcement is cheap and unambiguous, and the visual fallback was refused on its own merits.

### Labels

**Row emoji is hidden from VoiceOver everywhere.** It decorates the name it sits beside, and the dimmed 🎲 placeholder would announce "game die" on every List that has not got one. It stays audible in `EmojiField`, where it is the thing being edited rather than an ornament.

Spoken separators are commas, not `·`. Rows read:

| Row | Label |
| --- | --- |
| Lists index | `Lunch, Deck, 10 of 13 left` |
| Combine index | `Friday night, 3 Lists, Deck, 10 of 13 left` |
| Combo member, membership picker | `Lunch, 4 items` — plus the **Selected** trait when ticked |
| Item, dealt | `Pizza`, value `Dealt` |

**Dealt is a value, not a trait.** `.isSelected` says "Selected", which is the wrong word: nobody selected it, the deck dealt it. Selection *is* a trait in the membership form, where ticking is exactly that.

**The pinned Randomise bar is one accessibility element** — `.accessibilityElement(children: .combine)` over the button and its caption — reading `Randomise, Add an item to randomise, dimmed, button`, or `Randomise, Deck, 10 of 13 left, button`. The caption is the only thing that says *why* the button is dimmed, and it must not depend on a setting the user controls: putting it in `accessibilityHint` and hiding the visible caption would make the reason unreachable whenever "Speak Hints" is off.

`EmojiField` is a `UIViewRepresentable` and inherits no label, so it declares `accessibilityLabel("Emoji")` and an `accessibilityValue` of the emoji, or `None`. It is skippable in one swipe and nothing gates Save on it. Overriding `textInputMode` also stops a hardware keyboard typing into it; accepted, since the alternative is accepting arbitrary text into a one-grapheme column.

**Counts are pluralised with automatic grammar agreement.** `N items` and `N Lists` are not string interpolation — a one-item List otherwise renders "1 items" for everyone, VoiceOver or not.

### Dynamic Type

**Rows never clamp and never truncate.** They wrap and grow tall, which is correct for a list whose whole content is text the user wrote.

**The pinned bar never clamps either.** At the largest accessibility size it costs about a quarter of the screen permanently. Accepted: capping type size on the app's primary action is the least defensible place to do it, and the cost is scrolling in screens that hold few rows.

**The result sheet's detent grows at accessibility sizes** — `.medium` becomes `.large`. The fixed medium detent was checked only to `.accessibility3`; past that a long title either overflows or scales below half, and scaling down is a direct contradiction of the setting the user just turned up. `minimumScaleFactor(0.5)` goes back to being a safety net for one absurd Item rather than the thing holding the layout together. Everyone below the accessibility sizes sees the sheet exactly as designed.

## Localisation

**v1 ships English only — not yet translated, rather than never.** No second language is committed to and none is ruled out; what ships in v1 is the *mechanism*, because retrofitting a string catalogue over a finished app is the expensive order and adding one up front is nearly free.

It is also not optional. **Accessibility** requires automatic grammar agreement for `N items` and `N Lists`, and that is a String Catalog feature — without a catalogue in the bundle the string is looked up from, "1 items" ships to everyone.

### Where the catalogues live

A `Localizable.xcstrings` in each of the eight targets that render text — `Acknowledgements`, `AppFeature`, `CombineFeature`, `Components`, `ListDetailFeature`, `ListsFeature`, `RandomiseFeature` and `SettingsFeature`. `Models`, `Database`, `Preferences` and `App` render none and carry none. `defaultLocalization: "en"` on the package is what makes SwiftPM treat these as localisation resources; no target needs an explicit `resources:` entry.

**Every user-facing literal is written `bundle: #bundle`.** SwiftUI resolves a string against `Bundle.main` unless told otherwise, and every string in this app lives in a package target — so without the argument the lookup leaves the target's own bundle and finds nothing.

This deliberately departs from the convention in the sibling apps, which put one catalogue in the app target. Here AppHost renders no UI, so a catalogue there would collect nothing and translate nothing. Catalogues live where the text is.

### Composed strings

**Every composed string is one catalogue entry, separators included.** Row captions, the pinned bar's captions and the VoiceOver announcements are format strings with positional interpolation, not fragments joined in Swift:

| Kind | Entry |
| --- | --- |
| Lists index row, Deck | `%@ · Deck · %lld of %lld left` |
| Lists index row, VoiceOver | `%@, Deck, %lld of %lld left` |
| Combine index row, Deck | `%@ · ^[%lld Lists](inflect: true) · Deck · %lld of %lld left` |
| Item count | `^[%lld items](inflect: true)` |
| Combine announcement | `%@, from %@` |

A join is the one construction that cannot be translated: the translator receives fragments and no control over word order, and the separator — `·` in visible captions, a comma in spoken labels — is a punctuation decision made in code by someone thinking in English. Roughly fourteen entries once the plain and Deck variants and the pinned bar's three disabled prompts are counted, which is a small price for the phrase being the unit.

Two consequences follow. Each row carries **two authored strings**, the visible caption and the accessibility label, rather than deriving one from the other — which **Accessibility** already implies by spelling `·` as a comma. And grammar agreement nests inside a larger phrase, so a count keeps its inflection mid-format.

### Not localisable

**Licence bodies.** `Licenses.generated.swift` holds generated third-party text as `String` properties, rendered from a variable rather than a literal. Extraction therefore skips it automatically and `bundle:` does not belong on it. Recorded here so it is not later "fixed". The Acknowledgements screen's own chrome is localised like any other.

**User content.** List names, Combo names and Item titles are whatever the user typed. They enter localised strings only as `%@`, and are never inflected — grammar agreement applies to counts, not to content.

### Right-to-left

**Out of scope for v1 because it is unreachable, not because it is unwanted.** Layout direction resolves from the app's own localisation rather than the device's language, so an app shipping `en` alone runs left-to-right everywhere. Nothing about RTL is verified, and this says so.

The code stays direction-agnostic regardless, because that is SwiftUI's default rather than effort spent: the swipe action is `.leading`, not `.left`, and the pinned bar is full-width and centred. A first RTL translation would inherit a working layout instead of a rewrite.

### Enforcing the bundle argument

A missing `bundle: #bundle` is **invisible in v1**. The lookup misses, SwiftUI falls through to the key, and the English string renders correctly. Xcode's extraction gives no warning either — it scans a target's source literals, so the entry appears in the catalogue while the runtime lookup still goes to the wrong bundle. A full catalogue is not evidence of correct wiring.

A SwiftLint rule therefore guards the call sites at write time. The enumerated list is the decision and lives here; the rule itself is tooling, configured by convention:

`accessibilityLabel`, `AccessibilityNotification.Announcement`, `accessibilityValue`, `Button`, `confirmationDialog`, `Label`, `navigationTitle`, `Picker`, `Section`, `Text`, `Toggle`.

Reaching past `Text` is the point: `Text` is a minority of this app's strings, and **Accessibility**'s announcements — whose breakage is the hardest of all to notice, since they are silent either way — are not `Text` at all.

**The residual risk is accepted and named.** A source-level rule cannot see a runtime lookup, so a string that escapes the enumerated call sites escapes the check. The rejected alternative was a pseudolanguage pass per screen, where a correctly-wired string comes back accented and a mis-wired one stays plain English — the only check that exercises the actual failure. Without it, the first true verification of the localisation wiring is the first translated build.

## Constraints

- iPhone only, iOS 26 minimum. No iPad, Mac, or watch layouts. The iOS 26 floor is what makes ComposableArchitecture 2's `StoreActor` and `TestStoreActor` available.
- Tuist `Project.swift` wrapping a local SPM package; a thin AppHost target over modular SPM targets.
- ComposableArchitecture 2, as the `ComposableArchitecture2` product of the `TCA26` package, pinned to `branch: "main"`. The app is deliberately a showcase of it; tracking an untagged branch is an accepted risk.
- SQLiteData for persistence, with iCloud `SyncEngine` sync across one person's own devices. No sharing with other iCloud users in v1.
- English only in v1, with strings catalogued per target from the first build. No second language is committed to; none is ruled out.
- Synced tables require `UUID` primary keys, permit no `UNIQUE` outside the primary key, require an explicit `ON DELETE` on every foreign key, and reject reference cycles. Deletes are hard, and conflict resolution is field-wise last-writer-wins.
