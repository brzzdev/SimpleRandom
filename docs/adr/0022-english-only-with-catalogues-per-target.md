# English only, with string catalogues per target from the first build

v1 ships English only — stated as **not yet translated**, not as a non-goal. No second language is committed to and none is ruled out. What ships in v1 is the *mechanism*, because retrofitting a catalogue over a finished app is the expensive order and adding one up front is nearly free.

It was never optional anyway: ADR-0018 requires automatic grammar agreement for `N items` and `N Lists`, which is a String Catalog feature. Without a catalogue in the bundle the string is looked up from, "1 items" ships to everyone.

## Catalogues live per target

A `Localizable.xcstrings` in each of the eight targets that render text, and none in the four that do not. `defaultLocalization: "en"` on the package is what makes SwiftPM treat them as localisation resources. **Every user-facing literal is written `bundle: #bundle`** — SwiftUI resolves against `Bundle.main` unless told otherwise, and every string in this app lives in a package target.

This deliberately departs from the convention in the sibling apps, which put one catalogue in the app target. Here AppHost renders no UI, so a catalogue there would collect nothing and translate nothing.

Rejected: a single shared `Strings` target owning one catalogue (an indirection between every label and its words, and a thirteenth target everything depends on), and cataloguing only `Components` where the inflection is actually needed (which is not really cataloguing the app, so it defers exactly the retrofit this decision exists to avoid).

## Composed strings are whole phrases, separators included

Row captions, the pinned bar's captions and ADR-0017's announcements are one catalogue entry each with positional interpolation — `%@ · Deck · %lld of %lld left`, `%@, from %@` — **not fragments joined in Swift**. A join is the one construction that cannot be translated: the translator receives clauses with no control over word order, and the separator (`·` visible, a comma spoken) is punctuation chosen in code by someone thinking in English. Around fourteen entries, which is cheap for making the phrase the unit.

Two consequences worth having in writing: each row carries **two authored strings**, the visible caption and the accessibility label, rather than deriving one from the other; and grammar agreement nests inside a larger phrase, so a count keeps its inflection mid-format.

## Not localisable

**Licence bodies** — generated third-party text held as `String` properties and rendered from a variable, so extraction skips it automatically and `bundle:` does not belong on it. Recorded so nobody later "fixes" it; the Acknowledgements chrome *is* localised. **User content** — List names, Combo names and Item titles enter localised strings only as `%@`, and are never inflected.

## Right-to-left is out because it is unreachable

Layout direction resolves from the app's own localisation rather than the device's language, so an `en`-only app runs left-to-right on an Arabic device. RTL is not merely untested in v1; it cannot be reached. Verifying it under the pseudolanguage now was rejected as effort spent on a configuration no v1 user can reach. The code stays direction-agnostic anyway, because that is SwiftUI's default rather than effort spent — the swipe action is `.leading`, not `.left`.

## Enforcement, and the gap it leaves

**A missing `bundle: #bundle` is invisible in v1.** The lookup misses, SwiftUI falls through to the key, and the English string renders perfectly. Xcode's extraction is no help either: it scans a target's *source literals*, so the entry appears in the catalogue while the runtime lookup still goes to the wrong bundle. A full catalogue is not evidence of correct wiring.

A SwiftLint rule guards it at write time over an enumerated list of call sites, recorded in `CONTEXT.md`. Reaching past `Text` is the whole point — `Text` is a minority of this app's strings, and ADR-0017's announcements, whose breakage is hardest of all to notice because they are silent either way, are not `Text` at all.

**The residual risk is accepted and named.** A source-level rule cannot see a runtime lookup, so a string that escapes the enumerated call sites escapes the check. The rejected alternative was a pseudolanguage pass per screen — a correctly-wired string comes back accented, a mis-wired one stays plain English — the only check that exercises the actual failure. Without it, **the first true verification of the localisation wiring is the first translated build.**
