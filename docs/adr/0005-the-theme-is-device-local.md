# The theme is device-local and does not sync

The Light / Dark / System picker is stored as `@Shared(.appStorage("theme"))` and stays on the device it was set on. It is the only user preference in the app, and the only piece of state deliberately excluded from sync.

The Sharing library ships `.appStorage`, `.fileStorage` and `.inMemory` and has no `NSUbiquitousKeyValueStore` strategy, so syncing it costs either a bespoke `SharedKey` — a second sync mechanism alongside `SyncEngine`, with its own failure modes — or a `Preferences` table, which would burn append-only CloudKit schema (ADR-0002) on a colour scheme. Neither is worth it for something iOS itself treats as per-device: the system's own Light/Dark setting does not sync either.

## Consequences

`Theme` is app vocabulary, not domain vocabulary — it lives in `Models` for want of a better home but has no place in the ubiquitous language. The picker sits in its own `Appearance` section rather than under `About`, which is for facts about the app, not preferences.

Every screen is specified in both appearances as a result, and `Theme` is why the snapshot list in ADR-0019 doubles: each state is captured light and dark.
