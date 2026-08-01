# SQLiteData `SyncEngine`: requirements and constraints

Research for wayfinder ticket [#3](https://github.com/brzzdev/SimpleRandom/issues/3). What
SQLiteData's CloudKit `SyncEngine` demands of a schema, how it behaves, and what it will not do —
scoped to SimpleRandom: iPhone-only, iOS 26, one user's own devices, no `CKShare` collaboration.

## Sources

Primary sources only. The library was read from a local checkout at its released tag; Apple's
statements come from `developer.apple.com`.

| Ref | Source |
| --- | --- |
| `[SD-sync]` | `Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md` |
| `[SD-share]` | `Sources/SQLiteData/Documentation.docc/Articles/CloudKitSharing.md` |
| `[SD-prep]` | `Sources/SQLiteData/Documentation.docc/Articles/PreparingDatabase.md` |
| `[SD-pkmig]` | `Sources/SQLiteData/Documentation.docc/Articles/ManuallyMigratingPrimaryKeys.md` |
| `[SD-src]` | `Sources/SQLiteData/CloudKit/*.swift` — `SyncEngine`, `SyncEngineDelegate`, `SyncMetadata`, `IdentifierStringConvertible`, `PrimaryKeyMigration`, `Internal/Triggers` |
| `[SD-skill]` | `pfw-sqlite-data` skill — `references/icloud.md`, `references/interface/SQLiteData.swiftinterface` |
| `[AP-deploy]` | <https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema> |
| `[AP-design]` | <https://developer.apple.com/documentation/CloudKit/designing-and-creating-a-cloudkit-database> |
| `[AP-icloud]` | <https://developer.apple.com/documentation/Xcode/configuring-icloud-services> |
| `[AP-recordid]` | <https://developer.apple.com/documentation/CloudKit/CKRecord/ID> |
| `[AP-aps]` | <https://developer.apple.com/documentation/BundleResources/Entitlements/aps-environment> |
| `[AP-env]` | <https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.icloud-container-environment> |

Library read at `pointfreeco/sqlite-data` **1.8.2** (commit `26471412`). The hosted DocC pages
return HTTP 403 to automated fetches, so the articles were read as their source Markdown in the
repo — the same text the rendered docs are generated from.

Everything below is either quoted from a source or attributed to a specific file. Where the
library's documentation is silent and the answer was read out of the implementation, that is said
explicitly, because implementation detail is not a promise.

---

## 1. What a syncable table must look like

### Primary keys must be globally unique; `AUTOINCREMENT` is forbidden

> TL;DR: Primary keys must be globally unique identifiers, such as UUID, and cannot be an
> autoincrementing integer. Further, a `NOT NULL` constraint must be specified with an
> `ON CONFLICT REPLACE` action. — `[SD-sync]`

The reason is stated outright:

> SQLite makes it easy to add a primary key by using an `AUTOINCREMENT` integer. […] However, that
> does not play nicely with distributed schemas. That would make it possible for two devices to
> create a record with `id: 1`, and when those records synchronize there would be an irreconcilable
> conflict. — `[SD-sync]`

The canonical column definition:

```sql
"id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
```

> Tip: The `ON CONFLICT REPLACE` clause must be placed directly after `NOT NULL`. — `[SD-sync]`

`ON CONFLICT REPLACE` is the mechanism that lets you insert a `NULL` id and have SQLite substitute
the default — which is what the generated `Draft` types rely on `[SD-sync]`.

This is enforced in the type system as well as at runtime: `SyncEngine`'s tables must satisfy
`Base.PrimaryKey.QueryOutput: IdentifierStringConvertible` `[SD-src, SyncEngine.swift]`, and that
protocol's documentation says:

> A requirement of tables synchronized to CloudKit using a `SyncEngine`. You should generally
> identify tables using Foundation's `UUID` type or another globally unique identifier. It is not
> appropriate to conform simple integer types to this protocol.
> — `[SD-src, IdentifierStringConvertible.swift]`

A non-`UUID` identifier is permitted if it conforms to `IdentifierStringConvertible`, but then the
SQL default must come from a function you register in SQLite yourself, e.g.
`DEFAULT (customUUIDv7())` `[SD-sync]`.

**Provenance of `uuid()`:** it is not registered by SQLiteData or GRDB — neither package defines it
(`grep` for a `uuid` database function in `Sources/SQLiteData` finds only usages in docs and
`PrimaryKeyMigration.swift`). It is a function in Apple's system SQLite build; confirmed present in
the SQLite shipped with the current OS (`sqlite3 :memory: "select sqlite_version(), uuid()"` →
`3.51.0|6759750e-…`). Safe to rely on for an iOS 26 floor, but it is an Apple-platform fact, not a
library guarantee.

### Every table needs exactly one, non-compound primary key

> Every table being synchronized must have a single primary key and cannot have compound primary
> keys. This includes join tables that typically only have two foreign keys pointing to the two
> tables they are joining. — `[SD-sync]`

The article's own example gives a join table a surrogate `id` alongside its two FKs, and notes the
column may be dead weight for the app but is required by sync `[SD-sync]`.

**Not an issue for SimpleRandom**: Combine's selection is transient UI state, so there is no join
table in v1. Worth remembering if a saved `Combo` ever appears.

### Naming rules

The primary key is encoded into the CloudKit `recordName`, so CloudKit's identifier rules leak into
your data:

> The primary key of a row is encoded into the `recordName` of a `CKRecord`, along with the table
> name. There are restrictions on the value of `recordName`:
> * It may only contain ASCII characters
> * It must be less than 255 characters
> * It must not begin with an underscore
>
> If your primary key violates any of these rules, a `DatabaseError` will be thrown with a message
> of `SyncEngine/invalidRecordNameError`. — `[SD-sync]`

Apple is the authority for the underlying rule `[AP-recordid]`. The error is raised from a
`RAISE(ABORT, …)` inside a generated trigger `[SD-src, Internal/Triggers.swift]`. UUIDs satisfy all
three rules trivially.

Because `recordName` packs the primary key and the table name together, **table names may not
contain `:`** — `validateSchema()` throws `"Table name contains invalid character ':'"`
`[SD-src, SyncEngine.swift]`.

Column names must avoid CloudKit's reserved keys:

> certain key names are used internally by CloudKit and are reserved for their use only. This means
> those keys cannot be used as field names in your Swift data types or SQLite tables.
>
> While Apple has not published an exhaustive list of reserved keywords, the following should cover
> most known cases: `creationDate`, `creatorUserRecordID`, `etag`, `lastModifiedUserRecordID`,
> `modificationDate`, `modifiedByDevice`, `recordChangeTag`, `recordID`, `recordType`
> — `[SD-sync]`, repeated in `[SD-skill, icloud.md]`

Note the hedge: the list is Point-Free's best effort, not Apple's published set. A `createdAt`
column is fine; a `creationDate` column is not.

### Tables are opted into sync explicitly

> You must explicitly provide all tables that you want to synchronize. We do this so that you can
> have the option of having some local tables that are not synchronized to CloudKit, such as
> full-text search indices, cached data, etc. — `[SD-sync]`

`SyncEngine(for:tables:)` takes the list. So a future local-only table (a cache, an FTS index, a
"last randomised" scratch record) is available as an escape hatch from every constraint in this
document.

### Applied to SimpleRandom

```sql
CREATE TABLE "lists" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "title" TEXT NOT NULL DEFAULT '',
  "position" INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE TABLE "items" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "listID" TEXT NOT NULL REFERENCES "lists"("id") ON DELETE CASCADE,
  "title" TEXT NOT NULL DEFAULT '',
  "position" INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE INDEX "index_items_on_listID" ON "items"("listID");
```

Illustrative, not the settled schema — that is ticket #8's job. `STRICT` follows the DocC examples
`[SD-prep]`. There is deliberately no `UNIQUE` on `lists.title` (§7) and the FK carries an explicit
`ON DELETE` (§2).

---

## 2. Foreign keys, ordering columns, cascading deletes

### Foreign keys

> TL;DR: Foreign key constraints can be enabled and you can use `ON DELETE` actions to cascade
> deletions. — `[SD-sync]`

> This library uses that information to correctly implement synchronization behavior, such as
> knowing what order to synchronize records (parent first, then children), and knowing what
> associated records to share when sharing a root record. — `[SD-sync]`

Out-of-order arrival is handled for you:

> While it is possible for the sync engine to receive records in an order that could cause a foreign
> key constraint failure, such as receiving a child record before its parent, the sync engine will
> cache the child record until the parent record has been synchronized, at which point the child
> record will also be synchronized. — `[SD-sync]`

Three schema constraints follow, all checked in `validateSchema()` when the engine is constructed
`[SD-src, SyncEngine.swift]`:

**(a) `ON DELETE` must be `CASCADE`, `SET NULL` or `SET DEFAULT`.**

> Currently the only actions supported for `ON DELETE` are `CASCADE`, `SET NULL` and `SET DEFAULT`.
> In particular, `RESTRICT` and `NO ACTION` are not supported, and if you try to use those actions
> in your schema an error will be thrown when constructing `SyncEngine`. — `[SD-sync]`

`NO ACTION` is SQLite's implicit default, so **an FK written without an explicit `ON DELETE` clause
is rejected**. Every FK in a synced schema needs one spelled out.

> **Discrepancy between docs and implementation, verified in source.** The check is guarded by
> `if foreignKeys.count == 1` `[SD-src, SyncEngine.swift, validateSchema()]` — it only runs for
> tables with *exactly one* foreign key. A table with two or more FKs (a join table) currently
> passes validation with `NO ACTION`. Do not read that as permission: the documentation states the
> rule unconditionally, so the gap is best treated as an implementation detail that may close. Write
> the `ON DELETE` clause on every FK regardless.

**(b) An FK may not point at an unsynchronized table.** `validateSchema()` throws
`"Foreign key … references table … that is not synchronized. Update 'SyncEngine.init' to
synchronize …"` `[SD-src]`. So a synced table cannot reference a local-only one.

**(c) Reference cycles are rejected.** Not covered by the DocC articles; found in
`tablesByOrder(userDatabase:tables:tablesByName:)`, which topologically sorts the tables and throws
on a back-edge: `"Cycles are not currently permitted in schemas, e.g. a table that references
itself."` `[SD-src, SyncEngine.swift]`. This rules out a self-referencing parent pointer, which is
the natural way to model nested lists or list folders. Relevant if SimpleRandom ever wants list
groups.

### Cascading deletes

`ON DELETE CASCADE` is an ordinary SQLite constraint, applied locally on whichever device performs
the delete. It also produces the right result on the receiving device, because a remote delete is
applied as a real `DELETE` against your table (§3), which re-fires SQLite's cascade there. The
engine additionally enqueues explicit CloudKit deletes for descendant records
`[SD-src, SyncEngine.swift / Internal/Triggers.swift]`.

Net effect for SimpleRandom: deleting a list on one device removes its items everywhere. That is
the desired behaviour, and it needs no extra work — but see §3 on the absence of undo.

### Ordering columns

**There is no special support for ordering.** No CRDT sequence, no fractional indexing. A
`position: Int` column is an ordinary field and is therefore subject to the per-field
last-write-wins rule in §4. Two devices reordering the same list while offline merge field by field
and can end up with duplicate or interleaved positions.

That is the app's problem to absorb, not the library's. Practical mitigations: sort by
`(position, id)` so ties are at least stable and deterministic across devices, and/or renormalise
positions on write.

The docs do discuss `position` columns, but only for the *sharing* problem — keeping one user's
ordering out of another's view, by moving it to a table listed in `privateTables`:

> Sharing this record will mean also sharing the position of the list. That means when one user
> reorders their local lists, even ones that are private to them, it will reorder the lists for
> everyone shared. This is probably not what you want. — `[SD-share]`

**Not applicable to SimpleRandom v1.** Without collaboration, `position` can live directly on the
record and `privateTables` stays empty. Worth knowing that adding collaboration later would want
`position` moved to a side table — and moving a column is a rename-shaped migration, which §7 says
is impossible. If collaboration is even faintly plausible for v2, that is an argument for putting
`position` in its own table from day one.

---

## 3. Delete semantics

The DocC articles have no section on deletes, so this is read from the implementation
`[SD-src, Internal/Triggers.swift, SyncMetadata.swift, SyncEngine.swift]` and stated as such.

**Your tables get hard deletes. Tombstones exist only inside the library's own metadata database,
and only transiently.**

The mechanism is a pair of temporary triggers per synced table, discriminated by whether the write
came from app code or from the sync engine `[SD-src, Internal/Triggers.swift]`:

- `…_after_delete_on_<table>_from_user`, guarded by `!SyncEngine.$isSynchronizing`, sets
  `_isDeleted = true` on the matching `SyncMetadata` row. A further trigger on `SyncMetadata`
  (`after: .update(of: \._isDeleted)`) enqueues a delete for CloudKit.
- `…_after_delete_on_<table>_from_sync_engine`, guarded by `SyncEngine.$isSynchronizing`, deletes
  the `SyncMetadata` row outright — so an incoming delete is not echoed back to the server.

The tombstone is explicitly short-lived — `_isDeleted` is documented as being fully deleted once the
next batch of pending changes is processed `[SD-src, SyncMetadata.swift]`.

**What a delete on device A does on device B:** the row is removed from B's table for real. There is
no "deleted" flag on your row, no local trash, no recovery affordance. If SimpleRandom wants undo
for "delete list", it must model that itself — e.g. an `isArchived` / `deletedAt` column, filtered
out of queries, with the real `DELETE` happening later. Note the cost: an archived-then-purged row
still syncs its archive flag first, so undo works across devices, which is arguably the better
behaviour anyway.

Two coarser paths also delete local rows `[SD-src, SyncEngine.swift]`: a zone `.deleted` / `.purged`
event, and an iCloud account change —

> Deletes synchronized data locally on device and restarts the sync engine. This method is called
> automatically by the sync engine when it detects the device's iCloud account has logged out or
> changed. To customize this behavior, provide a `SyncEngineDelegate` … and implement
> `syncEngine(_:accountChanged:)`. — `[SD-src, SyncEngine.deleteLocalData()]`

That default is worth a product decision: signing out of iCloud silently wipes the user's lists off
the device. §4 shows the delegate hook that turns it into a prompt.

**Unverified:** the outcome of a delete on one device racing an edit on another. Neither the
articles nor the source state a documented delete-wins or edit-wins rule. Delete-wins is the likely
behaviour (once the server record is gone, an edit has nothing to attach to), but it is not
documented and should not be relied on.

---

## 4. Conflict resolution

> TL;DR: Conflicts are handled automatically using a "last edit wins" strategy for each column of
> the record. — `[SD-sync]`

> The library handles conflicts automatically, but does so with a single strategy that is currently
> not customizable. When a column is edited on a record, the library keeps track of the timestamp
> for that particular column. When merging two conflicting records, each column is analyzed, and the
> column that was most recently edited will win over the older data.
>
> We do not employ more advanced merge conflict strategies, such as CRDT synchronization. We may
> allow for these kinds of strategies in the future, but for now "field-wise last edit wins" is the
> only strategy available and we feel serves the needs of the most number of people. — `[SD-sync]`

Granularity is **per column, not per record**: two devices editing different columns of the same row
both keep their edits. The per-field timestamps ride inside the `CKRecord`'s values as
`_userModificationTime_<column>` keys `[SD-src, CloudKit+StructuredQueries.swift]`.

**Hooks to change it: none.** `SyncEngineDelegate` has exactly one requirement and it concerns
account changes, not conflicts `[SD-src, SyncEngineDelegate.swift]`:

```swift
public protocol SyncEngineDelegate: AnyObject, Sendable {
  func syncEngine(
    _ syncEngine: SyncEngine,
    accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
  ) async
}
```

> By default, a sync engine will clear out local data when detecting a logout or account change. To
> override this behavior, e.g. if you want to prompt the user and let them decide if they want to
> clear their local data or not, implement this method, and explicitly call
> `SyncEngine/deleteLocalData()` if/when the data should be cleared.
> — `[SD-src, SyncEngineDelegate.swift]`

The default implementation calls `deleteLocalData()` on `.signOut` and `.switchAccounts`, and does
nothing on `.signIn` `[SD-src]`. The doc comment carries a worked example of a `@MainActor
@Observable` delegate driving an alert — a ready-made pattern if SimpleRandom wants to ask before
wiping.

The one adjacent customisation point is the `SyncEngine.$isSynchronizing` SQL expression, which lets
**triggers** discriminate sync writes from user writes:

> if you have a trigger that refreshes an `updatedAt` timestamp on a row when it is edited, it would
> not be appropriate to do that when the sync engine updates a row from data received from CloudKit.
> But, if you have a trigger that updates a local FTS index, then you would want to perform that
> work regardless. — `[SD-sync]`

**Consequences for SimpleRandom.** Field-wise LWW suits list titles and item text well. It suits two
things badly:

- **Ordering** (§2) — merges field by field, produces position collisions.
- **Anything counter- or set-shaped.** If "pick history" or "times randomised" is ever modelled as
  an incrementing integer on the list row, concurrent picks on two devices clobber rather than sum.
  An append-only picks table with a UUID per row merges correctly and is the right shape.

---

## 5. Setup surface

### Entitlements and Info.plist

The library defers wholesale to Apple:

> The steps to set up your SQLiteData project for CloudKit synchronization are the same for setting
> up any other kind of project for CloudKit:
> * Follow the Configuring iCloud services guide for enabling iCloud entitlements in your project.
> * Follow the Configuring background execution modes guide for adding the "Background Modes"
>   capability to your project and turning on "Remote notifications".
> * If you want to enable sharing of records with other iCloud users, be sure to add a
>   `CKSharingSupported` key to your Info.plist with a value of `true`.
> * Once you are ready to deploy your app be sure to read Apple's documentation on Deploying an
>   iCloud Container's Schema. — `[SD-sync]`

What that concretely produces, per Apple:

> After you add the iCloud capability, Xcode updates your target's entitlements file to include the
> `com.apple.developer.icloud-container-identifiers`, which is an array that comprises the
> containers you select. […] Xcode automatically adds the Push Notifications capability to your
> target if you enable the CloudKit service because CloudKit uses push notifications to inform your
> app of server-side changes to your data. […] You must begin the container's name with `iCloud.`
> and use a unique string in reverse DNS notation. — `[AP-icloud]`

Resulting set:

| Key | Where | Value |
| --- | --- | --- |
| `aps-environment` | entitlements | added by Xcode with the Push Notifications capability `[AP-icloud]` |
| `com.apple.developer.icloud-container-identifiers` | entitlements | `["iCloud.<bundle id>"]` |
| `com.apple.developer.icloud-services` | entitlements | `["CloudKit"]` |
| `CKSharingSupported` | Info.plist | **not needed** — sharing is out of scope |
| `UIBackgroundModes` | Info.plist | `["remote-notification"]` |

The skill's `references/icloud.md` gives the same set as literal plist `[SD-skill]`. Under Tuist
these belong in the AppHost target's `entitlements:` file and `infoPlist:` dictionary. Note that
SQLiteData itself never mentions `aps-environment`; it arrives via the Push Notifications
capability and its value tracks the provisioning profile:

> Xcode sets the value of the entitlement based on your app's current provisioning profile. […] if
> you're using a development provisioning profile, Xcode sets the value to `development`.
> — `[AP-aps]`

### Container configuration

> containerIdentifier: The container identifier in CloudKit to synchronize to. If omitted the
> container will be determined from the entitlements of your app. — `[SD-skill, swiftinterface]`

The resolution order in code is: the `containerIdentifier` argument → the entitlement value → a stub
container in non-live contexts → otherwise throw `SchemaError.noCloudKitContainer`
`[SD-src, SyncEngine.swift]`. Omitting the argument and letting entitlements drive it is the right
default; the stub is what makes tests and previews work without a container.

### Wiring

```swift
extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.attachMetadatabase()
    }
    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    var migrator = DatabaseMigrator()
    // register migrations…
    try migrator.migrate(database)
    defaultDatabase = database
    defaultSyncEngine = try SyncEngine(for: database, tables: Item.self, List.self)
  }
}
```

> Before constructing a `SyncEngine` you must have already created and migrated your app's local
> SQLite database. — `[SD-sync]`

> You can only prepare the default sync engine a single time in the lifetime of your app.
> — `[SD-src, DefaultSyncEngine.swift]`

Under ComposableArchitecture 2 this is a `prepareDependencies` call in the `@main` entry point's
initialiser; features reach it via `@Dependency(\.defaultDatabase)` and
`@Dependency(\.defaultSyncEngine)` `[SD-skill]`.

`attachMetadatabase()` is only needed if the app queries `SyncMetadata` (§6). Without it, such
queries fail with `no such table: sqlitedata_icloud_metadata` `[SD-skill, icloud.md]`. SimpleRandom
probably does not need it in v1.

A `startImmediately` argument exists if sync should ever become opt-in — e.g. a paid feature
`[SD-skill, icloud.md]`. Default `true` is right here.

### Schema deployment and the development/production split

The library says nothing beyond pointing at Apple `[SD-sync]`, so this is Apple's story. It is the
single biggest operational trap in this document.

CloudKit creates the **development** schema just in time:

> You can create a schema using CloudKit Dashboard, or you can create a just-in-time schema by
> writing records programmatically. […] When you run your app, it adds that record type to the
> schema and saves the record. […] Saving a record works only if the user has signed into their
> iCloud account on their device. — `[AP-design]`

Production is **not** created automatically, and App Store builds see only production:

> During initial development of your app, you create your schema and add records for testing in the
> development environment. Apps in the App Store can access only the production environment. Before
> you publish your app, you must deploy the development schema to the production environment to copy
> over its record types, fields, and indexes. — `[AP-deploy]`

> As you continue to develop your app, you can add record types and fields to the development
> environment. To prevent conflicts, you can't delete record types or fields that are already in
> production. Every time you deploy the development schema, its additive changes merge into the
> production schema. — `[AP-deploy]`

Promotion is a manual console action:

> To deploy the development schema to production: Sign in to CloudKit Console at
> https://icloud.developer.apple.com/. Select the CloudKit Database app. In the top section, choose
> your container from the list. On the left, select Deploy Schema Changes. Review the pending
> deployment changes and click Deploy. — `[AP-deploy]`

Resetting is only free while nothing is in production:

> You can reset the development environment in the CloudKit Database app between runs of your app to
> remove all records. If your schema isn't in production, resetting the development environment also
> deletes all record types. Otherwise, the development schema reverts to the state of the production
> environment. — `[AP-deploy]`

Operating rule for SimpleRandom: iterate on debug builds, reset the development environment freely
while the schema is unsettled, then **Deploy Schema Changes before the first externally-distributed
build**, and stop resetting after that.

`com.apple.developer.icloud-container-environment` (`Development` | `Production`) is the override
knob if a build ever needs to point elsewhere `[AP-env]`.

**Caveat, flagged rather than asserted:** no Apple page found states in so many words that
*TestFlight* builds use CloudKit Production. The quotable statements are the App Store one above and
the provisioning-profile mapping on the APNs entitlement page `[AP-aps]`. Treat "deploy the schema
before TestFlight" as the safe operating rule, not a cited guarantee.

---

## 6. Offline and first-launch behaviour; observing sync state

### Offline and first launch — largely undocumented

The repo contains no documentation of offline behaviour and none of first-launch or new-device
catch-up. What is stated in primary source:

> When a sync engine is started it will upload all data stored locally that has not yet been
> synchronized to CloudKit, and will download all changes from CloudKit since the last time it
> synchronized.
>
> Note: By default, sync engines start syncing when initialized. — `[SD-src, SyncEngine.start()]`

From the implementation `[SD-src, SyncEngine.swift]`: the start task returns without doing anything
unless `container.accountStatus() == .available`, and CloudKit errors including `.networkFailure`,
`.networkUnavailable`, `.serviceUnavailable`, `.notAuthenticated` and `.zoneBusy` are treated as
retryable. Since every write goes to local SQLite first, offline use is ordinary local operation
with changes queued for later. **This is inferred from code, not promised by documentation.**

**There is no "initial sync complete" signal in the public API.** A fresh install on a second device
shows an empty state and then populates as records arrive. `isFetchingChanges` cannot stand in for
it: it is `false` before the first fetch begins, so gating a loading view on it yields a flash of
empty state. If SimpleRandom wants a first-run "syncing your lists…" affordance, it must be built
from app-level state — e.g. `await syncEngine.fetchChanges()` on first launch and a persisted
"has ever completed a fetch" flag.

**Design consequence:** the Lists tab's empty state has to be acceptable as *both* "you have no
lists" and "your lists have not arrived yet". Either make the copy neutral, or build the flag.

### Observing sync state

`SyncEngine` conforms to `Observation.Observable` directly, with a private `ObservationRegistrar`,
rather than via the `@Observable` macro — so that it can be `Sendable` rather than main-actor
`[SD-src, SyncEngine.swift]`. Four observable booleans:

- `isSendingChanges` — local → CloudKit in flight
- `isFetchingChanges` — CloudKit → local in flight
- `isSynchronizing` — true if either of the above is true
- `isRunning` — whether the engine is started at all

each documented as:

> It is an observable value, which means if it is accessed in a SwiftUI view, or some other
> observable context, then the view will automatically re-render when the value changes. As such, it
> can be useful for displaying a progress view to indicate that work is currently being done to
> synchronize changes. — `[SD-src, SyncEngine.swift]`

**Naming trap:** the *instance* property `isSynchronizing` (UI state) is a different thing from the
*static* `SyncEngine.$isSynchronizing` SQL expression used in trigger predicates (§4).

Manual control, for pull-to-refresh or a "Sync now" button in Settings:

> Use this method to ensure the sync engine immediately fetches all pending remote changes before
> your app continues. This isn't necessary in normal use, as the engine automatically syncs your
> app's records. It is useful, however, in scenarios where you require more control over sync, such
> as pull-to-refresh. — `[SD-skill, swiftinterface, fetchChanges(_:)]`

Also `sendChanges(_:)` and `syncChanges(fetchOptions:sendOptions:)` `[SD-skill, swiftinterface]`.

**Per-record** sync state lives in `SyncMetadata`, in a database separate from the app's, which must
be attached to be queryable `[SD-src, SyncMetadata.swift; SD-sync]`. Useful columns:
`lastKnownServerRecord`, `hasLastKnownServerRecord`, `share`, `isShared`, `userModificationTime`,
joined via the `syncMetadataID` helper present on every primary-keyed table `[SD-skill]`.
`hasLastKnownServerRecord` is the nearest thing to "has this row reached the server", though the
docs never frame it that way. Mostly unnecessary for SimpleRandom — the share columns are inert
without collaboration.

### Simulator caveat

> It is possible to develop your app with CloudKit synchronization using the iOS simulator, but you
> must be aware that simulators do not support push notifications, and so changes do not synchronize
> from CloudKit to simulator automatically. Sometimes you can simply close and re-open the app to
> have the simulator sync with CloudKit, but the most certain way to force synchronization is to
> kill the app and relaunch it fresh. — `[SD-sync]`

A simulator signed out of iCloud produces `"Not Authenticated"` /
`AccountUnavailableDueToBadAuthToken` errors and must be signed in roughly every 24 hours
`[SD-skill, icloud.md]`. Plan on verifying real sync across two physical devices.

---

## 7. What is NOT supported

### `UNIQUE` constraints and indexes, other than the primary key

> TL;DR: SQLite tables cannot have `UNIQUE` constraints on their columns in order to allow for
> distributed creation of records. — `[SD-sync]`

> Tables with unique constraints on their columns, other than on the primary key, cannot be
> synchronized. As an example, suppose you have a `Tag` table with a unique constraint on the
> `title` column. It is not clear how the application should handle if two different devices create
> a tag with the title "Family" at the same time. — `[SD-sync]`

Validated via `PRAGMA index_list` filtered on `isUnique && origin != "pk"`, throwing
`"Uniqueness constraints are not supported for synchronized tables."` `[SD-src, SyncEngine.swift]`.
The suggested workaround is to promote the column to the primary key `[SD-sync]` — useless here,
since primary keys must be UUIDs.

Non-unique indexes are fine. **Consequence for SimpleRandom: list titles cannot be enforced unique
at the database level.** Duplicate titles must either be tolerated or checked in app code, and the
app-code check is advisory only — it cannot prevent a duplicate arriving from another device.

### Compound, missing, or integer/auto-increment primary keys

All rejected — see §1. Note the library does ship a recovery path for an existing non-conforming
schema (`SyncEngine.migratePrimaryKeys(_:tables:uuid:)` plus a manual procedure `[SD-pkmig]`), but
that is for retrofitting sync onto a shipped app. SimpleRandom is greenfield and should simply be
born with UUID keys.

### Reference cycles

Rejected — see §2(c). No self-referencing tables.

### Column types

`BLOB` columns are special-cased rather than unsupported:

> All BLOB columns in a table are automatically turned into `CKAsset`s and synchronized to CloudKit.
> This process is completely seamless and you do not have to take any explicit steps to support
> assets. — `[SD-sync]`

> it is not recommended to store large binary blobs in a table that is queried often […] large
> binary blobs can slow down SQLite's ability to efficiently access the rows in your tables.
> — `[SD-sync]`

No relevance to SimpleRandom's text-only domain. No column type was found to be outright rejected.

### Migrations after the first shipped build

Additive only, and even additions have rules.

> TL;DR: Database migrations should be done carefully and with full backwards compatibility in mind
> in order to support multiple devices running with different schema versions. — `[SD-sync]`

**New tables are safe:**

> Adding new tables to a schema is perfectly safe thing to do in a CloudKit application. If a record
> from a device is synchronized to a device that does not have that table it will cache the record
> for later use. Then, when a device updates to the newest version of the app and detects a new table
> has been added to the schema, it will populate the table with the cached records it received.
> — `[SD-sync]`

**New columns must be nullable, or carry a default with `ON CONFLICT REPLACE`:**

> TL;DR: When adding columns to a table that has already been deployed to users' devices, you will
> either need to make the column nullable, or a default value must be provided with an
> `ON CONFLICT REPLACE` clause. — `[SD-sync]`

```sql
ALTER TABLE "lists"
ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
```

Without it, a record from an older device arriving at a newer one violates `NOT NULL` and simply
fails to sync — the article shows exactly this failure `[SD-sync]`. For a new column with no
sensible default, the docs concede the modelling cost: the field has to become optional in the Swift
type, and they call that "the unfortunate reality of a distributed schema" `[SD-sync]`.

**Flatly disallowed:**

> Certain kinds of migrations are simply not allowed when synchronizing your schema to multiple
> devices. They are:
> * Removing columns
> * Renaming columns
> * Renaming tables — `[SD-sync]`

Apple states the same from the CloudKit side:

> During development, you can change your schema as much as you want, but once it's deployed to
> production, you can't delete any part of it. You can only make additive changes, such as adding a
> new field to a record type, or adding new record types. — `[AP-design]`

And the general posture on table DDL:

> table definition SQL is fundamentally different from other SQL as it is frozen in time and should
> never be edited after it has been deployed to users. — `[SD-prep]`

Two distinct freezes are in play and they bite at different moments: the **CloudKit production
schema** freezes when it is deployed to production, and the **client schema** freezes when a build
reaches users. The second is the tighter one, and it lands at the first external build.

### Conflict strategy

Not customisable — see §4.

### Sharing (out of scope, but worth knowing)

`CKShare` collaboration is supported by the library but excluded from v1. Skipping it means: no
`CKSharingSupported` key, no scene-delegate `acceptShare(metadata:)` plumbing, no `privateTables`,
and the `SyncMetadata.share` / `isShared` columns stay empty `[SD-skill, icloud.md]`.

Sharing imposes extra schema rules that do **not** apply to v1 but would become retroactive
constraints if collaboration is ever added: only records with no foreign keys can be shared as
roots, and records with multiple foreign keys cannot be shared at all `[SD-share, SD-skill]`. Plus
the `position` point from §2. Cheap to keep in mind while the schema is still soft.

---

## Traps to carry into schema design (#8)

1. **`AUTOINCREMENT` is the reflex and it is wrong here.** `[SD-prep]`'s own examples use
   `"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT` — that article is the non-CloudKit baseline.
   Do not copy its DDL into a synced schema.
2. **Every foreign key needs an explicit `ON DELETE`**; the implicit `NO ACTION` is rejected, and
   the validator's current leniency for multi-FK tables is not a licence.
3. **No `UNIQUE` anywhere but the primary key** — list titles cannot be made unique.
4. **No self-referencing tables** — rules out nested lists / folders via a parent pointer.
5. **Avoid CloudKit's reserved column names** — `createdAt` yes, `creationDate` no.
6. **Deploy the CloudKit schema to production before the first external build**, and stop resetting
   the development environment after that.
7. **The schema is append-only from the first shipped build.** Getting column names right the first
   time is worth real effort; renames are impossible.
8. **Ordering under concurrent edits is the app's problem.** Sort by `(position, id)` at minimum.
9. **Nothing counter-shaped.** Model repeated events as append-only rows, never as an incremented
   integer.
10. **No first-sync-complete signal.** Design the empty state to read acceptably as "not synced
    yet", or build the flag yourself.
11. **Signing out of iCloud wipes local data by default.** Decide whether that should prompt, via
    `SyncEngineDelegate`.

## Open questions this research could not close

- **Delete racing an edit.** No documented rule; delete-wins assumed but unverified.
- **TestFlight → CloudKit Production.** Apple states it for App Store builds only.
- **Offline behaviour.** Read out of the implementation, not documented; treat as observed rather
  than guaranteed.
