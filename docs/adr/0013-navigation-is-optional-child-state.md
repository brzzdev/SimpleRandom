# Navigation is optional child state at every level

Every push and every sheet in the app is an optional child state wired with `.ifLet` — `.navigationDestination(item:)` for pushes, `.sheet(item:)` for sheets. No `[Path.State]` stack is introduced anywhere.

ComposableArchitecture 2 does have stacks — `[Path.State]` plus `.forEach(…, dismissStyle: .stack)` plus `navigationDestination(for: Path.StoreEnumeration.self)` — and they carry avoidable risk on an untagged branch (ADR-0001): `dismissStyle` **defaults to `.list`** rather than `.stack`, the library's own stack example omits it, and there is no stack case study on `main`. None of that buys anything at this app's depth.

Depth is one push on the Lists tab (`ListsFeature` → `ListDetail`) and two on Combine (`CombineFeature` → `ComboDetail` → `ListDetail`, because a member row pushes the real List detail — ADR-0014). The second level did not change the idiom; it is another `.navigationDestination(item:)`.

## Consequences

The push and the sheet are the same shape, which is one fewer thing to hold in your head, and the same `.ifLet` reasoning applies to both.

`var currentTab: Tab = .lists` is plain state and is **not persisted**. The app always opens on Lists, which is the reason it was opened; a cold launch landing on Settings because that is where you last were is a worse first frame, and there is no third preference key to sync or reset.

If the app ever grows past depth two on one tab, revisit — this ADR is an argument about depth, not a ban.
