# A Combo is built in one form, and nothing exists until Save

A Combo is defined in a single sheet — name, emoji, draw mode, **and** a checklist of every List, under a live "12 items in the pool." footer. Creating and editing are the same form. The Combo detail screen is then read-only membership plus the pinned Randomise button, with `Edit` reopening that form. There is no swipe-to-remove: membership has exactly one home, and the section footer says so.

## Considered options

Both alternatives were prototyped, and both broke on the same thing.

- **A separate membership picker sheet**, the straight mirror of the Lists tab's editor. It splits a Combo across two sheets and gives membership two homes — a multi-select sheet *and* a swipe-to-remove — for a screen whose only content is that membership.
- **The detail screen *is* the picker.** Fewest taps to a first draw, and it creates the Combo the instant you tap `+`.

**Nothing exists until Save** is the sharpest thing the chosen form buys. Under ADR-0009 every write is immediate and global, so both rejected variants put a record named "New Combo" on your other iPhones before it means anything.

## Consequences

- **Empty Lists are shown and are selectable** in the checklist, captioned as having no items. There is no minimum, and a List you are about to fill is a reasonable thing to add.
- **Index rows caption counts, not member names.** `3 Lists · 12 items`, or `3 Lists · Deck · 10 of 13 left`. Member names read better and were the alternative, but counts mirror the Lists tab and are the only option that shows a Combo's Deck running down without opening it.
- **A member row's caption never shows that List's own deck state** — a Combo pools every Item of every member regardless of what that List has dealt, so `Deck · 2 of 5 left` there would promise the Combo respects it (ADR-0007). Counts only, in Combine, everywhere.
- **A member row pushes the real List detail**, which is what forced `ListDetailFeature` out into its own target and took Combine to depth two (ADR-0013, ADR-0014).
- **The disabled Randomise button distinguishes three cases**, not one: no members, members but an empty pool, and — for an exhausted Deck — the button becomes Reshuffle rather than being disabled at all. All three are legal states.
- **Deleting a Combo confirms only when it has members**, and the message says the Lists are kept. What a Combo loses is an *arrangement*, not content.
- `+` is disabled when no Lists exist, and the tab carries a second empty state for that case.
