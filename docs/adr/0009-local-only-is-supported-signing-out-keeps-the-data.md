# Local-only is a supported state; signing out keeps the data

There is no sign-in prompt, no nag and no gate, ever. Every write goes to local SQLite first and `SyncEngine.start()` no-ops unless an iCloud account is available, so a device without one is an ordinary working app whose changes never leave it. The `Sync` row in Settings is the only place the app mentions iCloud.

A randomiser has nothing that *needs* an account, so a first-launch prompt would be the app asking for something for its own benefit. It also keeps a whole class of state out of the app: no "dismissed the prompt" flag, no re-prompt policy, no question about what happens when they sign in later — they just sync.

**`SyncEngine` deletes local data on an account change by default.** A `SyncEngineDelegate` overrides that, and SimpleRandom implements it:

- **`.signOut` — keep everything.** Signing out is simply the transition into the local-only state above, and an app that never required an account should not punish leaving one.
- **`.switchAccounts` — delete.** Those rows belong to the previous account; leaving them would leak one person's lists into another's app.
- **`.signIn` — nothing.**

**No alert either way**, which is the interesting half. An alert looks like the safe answer, but an account change can arrive while the app is backgrounded or not running, so the prompt either fires on next launch — asking about something that happened days ago, out of context — or is missed entirely. It also asks a question whose stakes the user cannot evaluate: "Remove" is unrecoverable and "Keep" is harmless, so it is a dialog with a right answer, which means the app should just pick it. `Delete All Lists` in Settings is already the deliberate way out.

## Consequences

- Accepted risk: on a shared iPhone, someone signing out (not switching) leaves the lists visible. Acceptable for a randomiser.
- **Deletes are hard, immediate and global.** No trash, no undo; deleting a List cascades its Items and its memberships. Soft delete was rejected for v1 and `deletedAt` reserved instead (ADR-0003). A delete racing an edit is undocumented by the sync layer and recorded as a known, accepted, unspecified outcome — the blast radius is one row of text.
- This is the app's most destructive available failure, and it fails in the direction of the library's default. It is also unreachable by a test, because the delegate method takes a live `SyncEngine`. ADR-0019 extracts the policy into a pure function for exactly that reason.
