# Reads are `@FetchAll` in feature state; there is no repository client

Features read the database by declaring `@FetchAll` / `@FetchOne` directly in `Feature.State`, and write through `@Dependency(\.defaultDatabase)` inside `store.addTask`, wrapped in `withErrorReporting`. Nothing sits between a feature and SQLiteData.

`@FetchAll`, `@FetchOne`, `@Fetch` and `@Shared` are on the `@ValueObservable` macro's allowlist and left untouched inside `Feature.State` — asserted in the library's own macro snapshot test, so this is a supported combination rather than a lucky one.

## Considered options

**A repository client** — the obvious TCA-shaped answer — was rejected on two counts. It returns snapshots rather than live updates, so observation would have to be rebuilt as `AsyncSequence`s on top of what `@FetchAll` already does. And `Database.inMemory()` gives every test a real database built by the real `migrator`, so a hand-written mock adds nothing but somewhere to drift from the real SQL.

(An earlier version of this reasoning credited `SQLiteDataTestSupport` with providing the test database. It does not — it ships `assertQuery` and nothing else. The database comes from `Database.inMemory()`. The claim was wrong; the design it justified is fine.)

## Consequences

- Randomness is the other seam that crosses into a library: `@Dependency(\.withRandomNumberGenerator)`. The selection, deck filtering, exhaustion check and reshuffle stay ordinary reducer logic. A bespoke `RandomiseClient` was rejected for the same reason as the repository — everything it would hide *is* the interesting logic, and a stub leaves "does the deck actually empty?" unexercised on the far side of the mock.
- **Primary keys come from the database**, not from insert sites: a custom SQLite function registered on the connection and used as each table's column default. `appDatabase()` registers a UUIDv7 generator, `inMemory()` a counting variant. One seam instead of a discipline at N call sites — no insert can forget an id. UUIDv7 is time-ordered, which quietly upgrades ADR-0010's `id` tie-break from arbitrary-but-consistent to creation-ordered.
- **`createdAt` is `@Dependency(\.date)`.** Without it, three Lists inserted in one write share a timestamp and fall through to a tie-break on a random UUID — a test that fails once a fortnight.
- **Open risk, recorded rather than resolved:** TCA26 contains no example of `@FetchAll` under a `TestStore` anywhere in its sources, tests or examples, and TCA 2's assertion closure operates on `State.DebugSnapshot` rather than on `State`. Whether observation-driven updates participate in the snapshot at all is unknown. The first feature test is written as a deliberate probe; if the answer is no, those assertions move to direct database reads, which `DatabaseTests` does anyway.
