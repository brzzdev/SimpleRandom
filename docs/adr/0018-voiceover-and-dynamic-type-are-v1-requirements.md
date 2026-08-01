# VoiceOver and Dynamic Type are v1 requirements

Not "we'll see at implementation time". The app is stock SwiftUI, so the cost is labels and one announcement rather than a parallel design — and the one genuinely hard case (ADR-0017) had to be decided while the sheet was still on paper, or it would have been decided silently by whoever wrote the view.

Stated non-goals for v1: Switch Control, Voice Control and Full Keyboard Access tuning beyond what standard controls give; VoiceOver rotor customisation; audio graphs. Reduce Motion needs nothing, because v1 ships no animation. Differentiate Without Colour needs nothing, because a dealt Item is secondary text *and* a checkmark.

## The decisions worth recording

**Row emoji is hidden from VoiceOver everywhere.** It decorates the name beside it, and the dimmed 🎲 placeholder is worse — "game die" on every List that has not got one, which is most of them early on. It stays audible in `EmojiField`, where it is the thing being edited rather than an ornament.

**Dealt is a value, not a trait.** `.isSelected` says "Selected", which is the wrong word: nobody selected it, the deck dealt it. Selection *is* a trait in the membership form, where ticking is exactly that.

**The pinned Randomise bar is one accessibility element**, combining the button and its caption. The caption is the only thing that says *why* the button is dimmed, and putting it in `accessibilityHint` with the visible caption hidden would make that reason unreachable whenever "Speak Hints" is off — a setting the user controls.

**Counts use automatic grammar agreement.** Not an accessibility issue at all: `N items` as plain interpolation renders "1 items" on screen for everyone. This is a String Catalog feature, and is why ADR-0022 is not optional.

**Nothing clamps Dynamic Type.** Rows wrap and grow tall, which is correct for a list whose entire content is text the user wrote. The pinned bar costs about a quarter of the screen at the largest accessibility size — capping type size on the app's primary action is the least defensible place to do it.

**The result sheet's detent grows at accessibility sizes** — `.medium` becomes `.large`. The fixed medium detent was only ever checked to `.accessibility3`; past that a long title either overflows or scales below half, and scaling down directly contradicts the setting the user just turned up. `minimumScaleFactor(0.5)` goes back to being a safety net for one absurd Item rather than the thing holding the layout together.

## Consequences

`EmojiField` is a `UIViewRepresentable` and inherits no label, so it declares one explicitly. Overriding `textInputMode` to force the emoji keyboard also blocks a hardware keyboard; accepted, since the alternative is arbitrary text in a one-grapheme column.

Three views ended up shared *and* carrying fiddly treatment, which is what justified the `Components` target (ADR-0014).
