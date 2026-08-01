# v1 does not foreclose the v2 reveal animation

The randomise animation is out of scope for v1 and **no seam is built for it**. What was in scope was whether v1 forecloses it, reviewed against the animation family that actually demands something — a **reel** that cycles other pool members before landing, not a plain fade-in, which is foreclosed by nothing.

Three definitions came out of that review. Each separates two moments that are **the same instant in v1**, which is why all three are free now and none is speculative structure.

**1. `drawToken` keeps its name; the contract is the reveal.** Renaming it to `revealToken` was rejected — `draw` is the domain's word, and importing `reveal` into the ubiquitous language to serve a v2 concern is exactly the cost this review exists to refuse. Instead the contract is stated where it matters: the haptic and the announcement fire when the result **becomes visible**. Under a reel the winner is known at t=0 and lands a second later, so a token left at the draw has VoiceOver saying "Pizza" before Pizza exists — ADR-0017's acknowledgement arriving before the event it acknowledges, which is worse than no acknowledgement. Nothing else would have told a future author to move it; the name says draw.

**2. The pool lives in `RandomiseFeature.State`.** Made explicit in ADR-0016. `RandomiseFeature` is a sheet child, so its view can see only its own state — if the pool were assembled inside a task and discarded, the v2 sheet would have no candidates to cycle and v2 would have to reshape a feature that is exhaustively tested by then. Priced rather than waved through: in Deck mode the remaining pool shrinks per draw, so exhaustive assertions carry that churn. A v1 cost paid for a v2 option, accepted deliberately.

**3. A draw row is written when the result is shown, not when it is computed.** Filed with the Deck rules (ADR-0006), because it is a rule about what a Deck *means*. A reel decides the winner at the tap; write the row there and dragging the sheet away mid-spin leaves the card **dealt and gone, unseen**. Reopen the List and it reads `9 of 13 left` with no memory of which Item vanished — and nothing is persisted that could show the user or let v2 un-deal it. This is the only finding a v2 author could get wrong in a way that destroys data rather than merely reading oddly.

## Reviewed and clean

Reduce Motion is already written conditionally, so it flips itself when v2 animates. The deferred Settings toggle lands later as one more device-local preference beside `Theme`, and the `Preferences` target already exists to hold it. **Again** being disabled during a spin, and the `.large` accessibility detent needing vertical room to reel, are conditions v2 adds for free.

Nothing here designs the animation. The animation and its Settings toggle remain out of scope.
