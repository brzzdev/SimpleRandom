# SimpleRandom

An iPhone app for picking one thing at random out of a list you made.

Three tabs:

- **Lists** — create Lists, add/edit/delete their Items, and randomise within one List.
- **Combine** — tick several Lists and randomise across their pooled Items.
- **Settings** — licences and credits.

## Domain model

### Ubiquitous language

A **List** has **Items**. These are the words used in conversation, in this document, in the UI, and in Swift.

`List` collides with SwiftUI's `List`. The domain word wins: the model type is `List`, and feature views that import SwiftUI qualify it as `Models.List`. The alternative — a second vocabulary for the code — was rejected as a permanent translation cost paid to avoid an occasional qualification.

### List

A named collection of Items, and the unit a randomise runs over.

| Field       | Type      | Notes                                    |
| ----------- | --------- | ---------------------------------------- |
| `id`        | `UUID`    | Primary key                              |
| `createdAt` | `Date`    | Sort key                                 |
| `emoji`     | `String?` | Optional, one grapheme cluster           |
| `name`      | `String`  | Trimmed, non-empty                       |
| `position`  | `Int?`    | **Reserved, unread in v1** — see below   |
| `updatedAt` | `Date?`   | **Reserved, unread in v1** — see below   |

### Item

A single candidate within a List. Text and nothing else: the app's job is picking one at random, and every additional field is something to design, sync, and render on the result sheet.

| Field       | Type     | Notes                                  |
| ----------- | -------- | -------------------------------------- |
| `id`        | `UUID`   | Primary key                            |
| `createdAt` | `Date`   | Sort key                               |
| `listID`    | `UUID`   | Foreign key to `List`, `ON DELETE CASCADE` |
| `position`  | `Int?`   | **Reserved, unread in v1** — see below |
| `title`     | `String` | Trimmed, non-empty                     |
| `updatedAt` | `Date?`  | **Reserved, unread in v1** — see below |
| `weight`    | `Int?`   | **Reserved, unread in v1** — see below |

### Rules

**Ownership.** An Item belongs to exactly one List. Deleting a List deletes its Items. The same text appearing in two Lists is two rows, which costs nothing — the Combine tab pools across Lists anyway.

**No nesting.** A List cannot contain a List. The sync layer rejects reference cycles between tables, so this is structural rather than a product choice.

**Ordering.** Both Lists and Items sort by `createdAt` ascending — insertion order, newest last. There is no reorder gesture in v1. Order carries no meaning for a randomiser; it exists so a thing stays where the user put it.

**Uniqueness.** None. Two Items in a List may have identical titles, and two Lists may share a name. This is deliberate: under uniform selection, adding "Pizza" twice doubles its odds, so repetition is the user's own weighting mechanism. It is also the only enforceable answer — the sync layer permits no `UNIQUE` constraint outside the primary key, so a uniqueness rule could not survive two devices editing offline.

**Selection.** Uniform across the Items in scope. `weight` is present in the schema and read by nothing.

**Bounds.** No maximum. An empty List is legal — you have just made it — and its Randomise button is visible but disabled, with a prompt to add something. A one-item List randomises normally and always returns that item.

### Reserved columns

The CloudKit schema is append-only from the first shipped build: columns can never be renamed, moved, or dropped. `position`, `updatedAt`, and `weight` are therefore written into v1's schema and read by nothing, because reserving them is free now and impossible later.

`position` in particular is the most likely v1.x request (drag to reorder) and the column a future `CKShare` would want relocated to a side table — a move, and so unavailable after ship.

## Constraints

- iPhone only, iOS 26 minimum. No iPad, Mac, or watch layouts. The iOS 26 floor is what makes ComposableArchitecture 2's `StoreActor` and `TestStoreActor` available.
- Tuist `Project.swift` wrapping a local SPM package; a thin AppHost target over modular SPM targets.
- ComposableArchitecture 2, as the `ComposableArchitecture2` product of the `TCA26` package, pinned to `branch: "main"`. The app is deliberately a showcase of it; tracking an untagged branch is an accepted risk.
- SQLiteData for persistence, with iCloud `SyncEngine` sync across one person's own devices. No sharing with other iCloud users in v1.
- Synced tables require `UUID` primary keys, permit no `UNIQUE` outside the primary key, require an explicit `ON DELETE` on every foreign key, and reject reference cycles. Deletes are hard, and conflict resolution is field-wise last-writer-wins.
