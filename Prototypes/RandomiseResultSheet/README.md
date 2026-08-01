# PROTOTYPE — The Randomise result sheet

Throwaway. Answers [issue #11](https://github.com/brzzdev/SimpleRandom/issues/11): what does the sheet
showing a random element look like, given it has no animation in v1?

In-memory data, no SQLiteData, no TCA, plain SwiftUI. It is about shape, not architecture. The screen
behind the sheet is variant A of [#10](https://github.com/brzzdev/SimpleRandom/issues/10), stripped to
its rows and its pinned Randomise button, so detents can be judged against real content.

## Run

```sh
./Prototypes/RandomiseResultSheet/run.sh
```

Compiles straight to an iPhone 17 Pro (iOS 26) simulator with `swiftc` — no Xcode project.

## Driving it

- The black strip at the top is prototype chrome: `‹ ›` cycle the variant, the layers icon picks the
  scenario, `Aa` forces the largest accessibility text size, and the sun/moon flips the appearance.
- Tap **Randomise** to open the sheet, then re-roll from inside it. The deck state is shared with the
  backdrop, so dealt rows tick over behind the sheet as you draw.
- Launch args for screenshots: `--variant B --scenario deck --sheet --dark --big --exhaust`.

## Scenarios

| | Why it is here |
| --- | --- |
| Plain · 6 items | Two "Pizza"s in six: re-rolling repeats often, which is the whole problem |
| Plain · 1 item | Every re-roll is a repeat by definition |
| Plain · long text | A title that will not fit on one line at any size |
| Deck · 3 of 5 left | Deck progress mid-run |
| Deck · 1 left | One re-roll away from the exhausted state |
| Combo · Food | "Pizza" is in both member Lists, so provenance is the only thing telling them apart |

## The three variants

**A won**, and its chosen answers are folded back into `VariantA.swift`: no Done button, Again
disabled on a one-item pool, and nothing at all around the result on the Lists path. B and C are
left in place as the record of what was rejected and why.

| | A — Centre stage | B — Peek bar | C — The pool |
| --- | --- | --- | --- |
| Detent | `.medium` | `.height(200)`, background interaction on | `.fraction(0.9)` |
| Result | centred, `.largeTitle`, up to 4 lines | leading, `.title`, up to 3 lines | centred, `.largeTitle`, over the pool |
| Re-roll | full-width **Again** | circular dice, trailing | full-width **Again**, pinned |
| Dismiss | drag only | drag only | **Done** in the toolbar |
| Provenance (Combine) | line above the result | in the caption line | line above the result, and on every row |
| Proof a draw happened | haptic only (medium impact) | haptic (selection) + **Draw N** counter | haptic (success) + the pool row highlight moves |
| Exhausted Deck | full stop: icon, headline, **Reshuffle** | caption + "All N dealt" + shuffle button | headline over the all-dealt pool |

## What the prototype is actually asking

- **Is a haptic enough on its own?** Variant A bets yes and shows nothing visual on a repeat. B and C
  bet no and each pay a different price for the proof.
- **How much of the sheet should be result?** A is nearly all result. C is mostly context.
- **Does the sheet need to hide the List, or benefit from showing it?** B deliberately leaves it live.

## Noted while building

- In B the sheet is translucent and short, so the **pinned Randomise button on the screen behind
  glows through it**. If B wins, that button has to hide or disable while the sheet is up.
- The exhausted state is only reachable by re-rolling to the end *inside* the sheet — #10 already
  turns the pinned button into **Reshuffle** once the deck is out, so you can never open the sheet
  into it. Worth confirming that is intended.
