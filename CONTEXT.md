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
| `drawnAt`   | `Date?`  | `nil` means undealt — see **Drawing**  |
| `listID`    | `UUID`   | Foreign key to `List`, `ON DELETE CASCADE` |
| `position`  | `Int?`   | **Reserved, unread in v1** — see below |
| `title`     | `String` | Trimmed, non-empty                     |
| `updatedAt` | `Date?`  | **Reserved, unread in v1** — see below |
| `weight`    | `Int?`   | **Reserved, unread in v1** — see below |

### Combo

A named set of Lists whose Items are pooled and drawn from together. A Combo references its member Lists by id rather than copying them, so it stays live as those Lists gain, lose and rename their Items.

| Field       | Type       | Notes                                  |
| ----------- | ---------- | -------------------------------------- |
| `id`        | `UUID`     | Primary key                            |
| `createdAt` | `Date`     | Sort key                               |
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

A Combo's deck state cannot live on `Item`, because an Item can belong to many Combos.

### Rules

**Ownership.** An Item belongs to exactly one List. Deleting a List deletes its Items. The same text appearing in two Lists is two rows, which costs nothing — the Combine tab pools across Lists anyway.

**No nesting.** A List cannot contain a List. The sync layer rejects reference cycles between tables, so this is structural rather than a product choice. A Combo *does* hold Lists, but as a separate table pointing at them: the graph is `Combo ──< ComboList >── List ──< Item` plus `Combo ──< ComboDraw >── Item`, which is acyclic and therefore allowed. This is why combining is its own entity rather than a mode of `List`.

**Combining.** A Combo's pool is every Item of every member List, flattened. Membership is deduplicated by `listID` when the pool is built: no `UNIQUE` is available outside the primary key, so two devices adding the same List offline can produce duplicate `ComboList` rows, and left alone that would silently double the List's weight. Duplicate *Items* are not deduplicated — the same text in two member Lists is two entries and two chances, exactly as within one List.

Membership is a join table rather than a `[UUID]` column on `Combo` because conflict resolution is field-wise last-writer-wins: with an array, two devices each adding a different List offline means one edit is silently lost, whereas rows merge. Deleting a List also cascades its memberships away for free, instead of leaving a dangling id to filter at read time forever. The Combo then silently shrinks; nothing warns first.

**Ordering.** Lists, Items and Combos all sort by `createdAt` ascending — insertion order, newest last. There is no reorder gesture in v1. Order carries no meaning for a randomiser; it exists so a thing stays where the user put it.

**Uniqueness.** None. Two Items in a List may have identical titles, and two Lists — or two Combos — may share a name. This is deliberate: under uniform selection, adding "Pizza" twice doubles its odds, so repetition is the user's own weighting mechanism. It is also the only enforceable answer — the sync layer permits no `UNIQUE` constraint outside the primary key, so a uniqueness rule could not survive two devices editing offline.

**Selection.** Uniform across the Items in scope — the Items of one List, or the pooled Items of a Combo. Every Item in the pool has equal probability, so a 100-item List dominates a 3-item one in a Combo they share. Picking a member List first and then an Item within it was rejected: it is a second selection concept, and it breaks the rule that adding "Pizza" twice doubles its odds. `weight` is present in the schema and read by nothing.

**Drawing.** A plain List (`drawMode == .independent`) draws uniformly over all its Items on every tap, with no memory: the same Item twice in a row is legal and is not suppressed. A **Deck** (`drawMode == .deck`) draws only over Items whose `drawnAt` is `nil`, stamping the drawn one; when none are left the Deck is **exhausted** and offers **Reshuffle**, which clears every `drawnAt` on the List. Reshuffle is available at any time, not only at exhaustion.

A Combo draws the same two ways, over its pool, but keeps its own deck state: a plain Combo pools everything on every tap, and a Combo Deck draws only over pooled Items with no `ComboDraw` row, inserting one for the Item it deals. It is **exhausted** when its row count equals its pool size, and **Reshuffle** hard-deletes that Combo's rows.

**Decks are independent per surface.** A Combo's draw is governed only by its own `drawMode` and its own `ComboDraw` rows. Member Lists' `drawMode` and `drawnAt` are neither read nor written — a Combo always pools every Item of every member List, including ones already dealt within their own List, and drawing from a Combo never stamps `Item.drawnAt`. "Dealt in Movies" and "dealt in Friday night" are separate facts. Nesting the two deck states was rejected: they compose into behaviour that is hard to predict, and an exhausted member List would silently shrink the pool with nowhere sensible to put its Reshuffle.

`drawnAt` is a property of the row and nothing else touches it. A new Item arrives undealt, so adding one to an exhausted Deck un-exhausts it. Editing an Item's title does not clear its `drawnAt` — identity is the row, not the text. Switching a Deck back to plain preserves `drawnAt`, so switching back resumes where it left off. Nothing resets a Deck on launch or on a timer.

Randomness comes from `@Dependency(\.withRandomNumberGenerator)`; the selection, exhaustion and reshuffle logic itself lives in the reducer rather than behind a client, so tests seed the generator and assert real draws.

**Draw results are not persisted.** There is no last-result memory and no draw history table; `Item.drawnAt` and a `ComboDraw` row are the only records that a draw happened. A Combo's result names the Item's source List alongside the title — load-bearing precisely because duplicate Items are not deduplicated, so "Pizza" from Lunch and "Pizza" from Dinner would otherwise be indistinguishable.

**Bounds.** No maximum, and no minimum. An empty List is legal — you have just made it — and its Randomise button is visible but disabled, with a prompt to add something. A one-item List randomises normally and always returns that item — and as a Deck, exhausts after a single draw.

The same holds for a Combo: zero member Lists is legal, with Randomise disabled and a prompt to add one; one member List is legal and behaves like that List; and members that are all empty leave an empty pool, which disables Randomise too. There is no "combining needs two Lists" rule — it would block building a Combo up one List at a time.

### Reserved columns

The CloudKit schema is append-only from the first shipped build: columns can never be renamed, moved, or dropped. `position`, `updatedAt`, and `weight` are therefore written into v1's schema and read by nothing, because reserving them is free now and impossible later. This applies to every table, join tables included — `ComboList.position` is what a future "reorder a Combo's Lists" would want.

`position` in particular is the most likely v1.x request (drag to reorder) and the column a future `CKShare` would want relocated to a side table — a move, and so unavailable after ship.

## Constraints

- iPhone only, iOS 26 minimum. No iPad, Mac, or watch layouts. The iOS 26 floor is what makes ComposableArchitecture 2's `StoreActor` and `TestStoreActor` available.
- Tuist `Project.swift` wrapping a local SPM package; a thin AppHost target over modular SPM targets.
- ComposableArchitecture 2, as the `ComposableArchitecture2` product of the `TCA26` package, pinned to `branch: "main"`. The app is deliberately a showcase of it; tracking an untagged branch is an accepted risk.
- SQLiteData for persistence, with iCloud `SyncEngine` sync across one person's own devices. No sharing with other iCloud users in v1.
- Synced tables require `UUID` primary keys, permit no `UNIQUE` outside the primary key, require an explicit `ON DELETE` on every foreign key, and reject reference cycles. Deletes are hard, and conflict resolution is field-wise last-writer-wins.
