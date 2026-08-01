# PROTOTYPE — Combine tab and Combo detail UI

Throwaway. Answers [issue #13](https://github.com/brzzdev/SimpleRandom/issues/13): what do the
Combine tab and the Combo detail screen look like, and where do you choose a Combo's member Lists?

In-memory data, no SQLiteData, no TCA, plain SwiftUI. It is about shape, not architecture.

## Run

```sh
./Prototypes/CombineTabUI/run.sh
```

Compiles straight to an iPhone 17 Pro (iOS 26) simulator with `swiftc` — no Xcode project.

## Driving it

- The black strip at the top is prototype chrome: `‹ ›` cycle the variant, and the menu on the
  right swaps the store — **Sample**, **No Combos** (Lists exist, no Combos yet), **No Lists**
  (nothing to combine at all).
- The Lists tab is a stub; [issue #10](https://github.com/brzzdev/SimpleRandom/issues/10) settled it.
  It is here so the sample Lists are visible while judging a Combo, and so the real tab bar is in
  the picture when judging the bottom of the screen.
- The result sheet is the variant A already chosen in [issue #11](https://github.com/brzzdev/SimpleRandom/issues/11),
  with the Combine path's extra secondary line naming the source List.
- `--variant B --detail` as launch arguments boots straight into a Combo detail (used for screenshots).

## What is *not* up for grabs

[Issue #10](https://github.com/brzzdev/SimpleRandom/issues/10) settled that Combine mirrors the
Lists tab: same row shape (emoji · name · caption), same large title and `+`, same pull to refresh,
same full-width Randomise button pinned in the bottom safe area, same swipe to delete. All three
variants do that. They differ on the one genuinely open thing: **where membership is chosen and
edited** — and, as a rider, what a Combo's row caption says.

## The three variants

|  | A — Picker sheet | B — One sheet | C — Detail is picker |
| --- | --- | --- | --- |
| Create | `+` → editor sheet (name/emoji/mode) → saves → pushes to an empty detail | `+` → one form: name/emoji/mode **and** the List checklist | `+` creates "New Combo" immediately and pushes in |
| Choose Lists | detail's `+` → full-height multi-select sheet | a `Lists` section inside that same form | the detail itself — members on top, `Other Lists` below, tap to toggle |
| Remove a List | trailing swipe on the member row | untick it in the form | tap the member row |
| Edit name/emoji/mode | leading swipe on the index row | `Edit`, same form | `Edit` → small identity-only sheet |
| Detail screen is | the member Lists | the member Lists, read-only | every List, membership as checkmarks |
| Row caption | `3 Lists · 12 items` | `Lunch · Dinner · Takeaway` | `🥪🍝🥡  12 items` |
| Half-made Combo can sync | yes (created before Lists are picked) | no (nothing exists until Save) | yes, and unnamed |

## The verdict

**B won**, and the answers below are folded into it. A and C stay as they were, as the record of
what was on offer.

- **Row caption is counts** (A's), not names: it mirrors the Lists tab and is the only option that
  shows a Deck running down from the index.
- **A member row pushes the real List detail** — the same screen the Lists tab pushes, Randomise
  bar and all. Tap `Lists` in the tab bar and open a List to see it is literally the same view.
- **Deleting a Combo confirms only when it has members**, as the prototype already did.

## Held the same across all three

- **A member List's row never shows its own deck state.** Decks are independent per surface
  ([issue #7](https://github.com/brzzdev/SimpleRandom/issues/7)): a Combo pools every Item of every
  member regardless of what that List has dealt. `Deck · 2 of 5 left` on a member row would promise
  the Combo respects it. Counts only.
- **Empty Lists are shown and are selectable.** There is no minimum, and a List you are about to
  fill is a reasonable thing to add. The caption reads `No items`, tertiary.
- **Three distinct disabled prompts**, not one "nothing to draw": `Add a List to randomise`,
  `The Lists in this Combo have no items`, and — for an exhausted Deck — the button becomes
  **Reshuffle** rather than being disabled at all.
- **Deleting a Combo confirms only when it has members**, and the message says the Lists are kept:
  a Combo owns no Items, so deleting one throws away an arrangement, not content.
- **`New Combo` is disabled when no Lists exist**, with its own empty state on the tab.
