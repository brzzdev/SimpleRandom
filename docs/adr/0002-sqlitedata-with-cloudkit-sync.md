# SQLiteData with CloudKit sync, and an append-only schema

Persistence is SQLiteData, with `SyncEngine` keeping one person's iPhones in step over their CloudKit private database. That choice is not free-standing: it imposes constraints on the schema that every other data decision in this repo is downstream of, and most of them cannot be walked back after the first shipped build.

The constraints, verified against `pointfreeco/sqlite-data` @ 1.8.2 rather than assumed:

- **Primary keys are globally unique `UUID`s.** `AUTOINCREMENT` integers are explicitly forbidden — two devices would both create `id: 1`. Every synced table needs exactly one non-compound primary key, join tables included.
- **No `UNIQUE` constraint outside the primary key**, validated when the engine is constructed. See ADR-0004.
- **Every foreign key carries an explicit `ON DELETE`** — `CASCADE`, `SET NULL` or `SET DEFAULT`; SQLite's implicit `NO ACTION` is rejected. Foreign keys also order the sync itself, and may not point at unsynchronised tables. (The library's validation currently only fires when a table has exactly one foreign key. Write the clause everywhere regardless; the documentation states the rule unconditionally and the gap may close.)
- **Reference cycles are rejected.** This is what makes "a List cannot contain a List" structural rather than a product choice.
- **Conflict resolution is field-wise last-writer-wins and is not customisable.** `SyncEngineDelegate` has exactly one method and it is about account changes. Nothing in the schema may be counter-shaped — repeated events are append-only rows, never an incremented integer.
- **Deletes are hard on every device.** Tombstones exist only transiently in the library's separate metadata database.
- **The schema is append-only from the first shipped build.** Columns can never be renamed, moved or dropped; CloudKit production accepts additive changes only. New tables are safe — records cache until the table exists.

## Consequences

The append-only rule is the one with the longest shadow: it is why unread columns are reserved up front (ADR-0003), why deck state was moved off `Item` before ship rather than after (ADR-0006), and why the theme is not a `Preferences` table (ADR-0005).

Operationally: CloudKit auto-creates the *development* schema just-in-time but never production. **Deploy Schema Changes in the CloudKit Console before the first external build**, and stop resetting the development environment after that. Entitlements are `aps-environment`, `com.apple.developer.icloud-container-identifiers` and `com.apple.developer.icloud-services`, with `UIBackgroundModes: [remote-notification]`. No `CKSharingSupported` — sharing is out of scope (ADR-0006 covers what v1 does to keep it possible).
