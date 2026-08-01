# PROTOTYPE — Lists tab and List detail UI

Throwaway. Answers [issue #10](https://github.com/brzzdev/SimpleRandom/issues/10): what do the Lists
tab and the List detail screen look like, and how do you add, edit and delete?

In-memory data, no SQLiteData, no TCA, plain SwiftUI. It is about shape, not architecture.

## Run

```sh
./Prototypes/ListsTabUI/run.sh
```

Compiles straight to an iPhone 17 Pro (iOS 26) simulator with `swiftc` — no Xcode project.

## Driving it

- The black strip at the top is prototype chrome: `‹ ›` cycle the variant, **Sample / Empty** swaps
  the store so you can see the empty and first-launch states.
- The Combine and Settings tabs are placeholders — they exist so the real tab bar is in the picture
  when judging the bottom of the screen.
- The randomise result sheet is deliberately a stub; it is [issue #11](https://github.com/brzzdev/SimpleRandom/issues/11).
- `--variant B --detail` as launch arguments boots straight into a detail screen (used for screenshots).

## The three variants

| | A — Sheets & pinned bar | B — Inline & FAB | C — Cards & header |
| --- | --- | --- | --- |
| Create a List | toolbar `+` → editor sheet | inline field at the bottom of the list | dashed "New List" card → editor sheet |
| Rename | swipe → Edit → sheet | context menu → row becomes a field | context menu → sheet |
| Delete | swipe | swipe or context menu | context menu |
| Add an Item | toolbar `+` → sheet | inline field, keyboard stays up | "Add item" row → sheet |
| Edit an Item | tap → sheet | edit in place | tap → sheet |
| Randomise | full-width button pinned in the bottom safe area | circular FAB floating bottom-trailing, hides with the keyboard | on every index card, **and** in a scrolling detail header |
| Draw mode | in the editor sheet | context menu toggle | segmented control in the detail header |
| Empty index | `ContentUnavailableView` + button | prompt over an autofocusable field | just the dashed card |
