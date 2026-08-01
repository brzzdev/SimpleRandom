# A re-roll is acknowledged by a haptic and an announcement, nothing visual

The result sheet re-rolls in place, and a plain List draws uniformly with no repeat suppression (ADR-0004). So a re-roll that lands on the Item already shown changes nothing on screen, and is **visually indistinguishable from a dead button**.

The acknowledgement is a medium-impact haptic on every draw, unconditional — there is no haptics toggle in Settings — and, for VoiceOver, an `AccessibilityNotification.Announcement` at `.high` priority. Both fire from the view on `drawToken` changing (ADR-0016): two channels acknowledging one event. Nothing visual ships.

## Considered options

Two visual answers were built as prototypes and rejected:

- **A draw counter** that always ticks. Scoreboard language for something that is not a game — and ADR-0018 shows it coming back in disguise as a changed `accessibilityValue`, rejected there too.
- **A pool view** where the highlight visibly moves. Two-thirds of the sheet given over to rows you were just looking at.

## Consequences

**With system haptics off, a repeated re-roll is indistinguishable from a dead button. No fallback ships.** This is the same reasoning that refused repeat-suppression in the first place: Deck mode is the app's real answer to "I don't want repeats", and a second design maintained only for a minority path is worse than the gap it fills.

The VoiceOver channel exists because the gap there was worse, not better: nothing in SwiftUI announces changed `Text` inside a presented sheet, so **Again** was silent rather than merely ambiguous. It announces `Pizza`, or `Pizza, from Lunch` on the Combine path, or `That's the whole deck` when a re-roll lands on an exhausted Deck. The source List's *emoji* is excluded — VoiceOver reads it by its CLDR name, so it would put "sandwich" in front of the only word that disambiguates.

**This leaves the VoiceOver path better served than the sighted path.** Accepted, not overlooked: an announcement is cheap and unambiguous, and the visual fallback was refused on its own merits above.

The announcement fires **on re-roll only** — the sheet's presentation already reads the opening result, and announcing there talks over it. The token's initial value gives that for free.

It fires from the view rather than as an effect from the reducer: an announcement is a UI-layer acknowledgement, and the test suite should not gain a seam that only ever tests its own mock. Consequently the haptic and the announcement are untested and get no seam — a haptic that stops firing is a cosmetic regression on a screen you use constantly, and ADR-0019 reserves reshaping production code for testability to failures that destroy data.

**Again is disabled on a one-item pool**, where every draw is a repeat by definition and the haptic would be the only thing distinguishing a working button from a broken one.
