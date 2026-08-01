# No uniqueness anywhere; duplicates are the user's weighting

Two Items in a List may have identical titles, and two Lists — or two Combos — may share a name. Nothing in the app deduplicates, warns, or normalises case and whitespace.

This is a product decision and a forced one at the same time, which is why it is worth writing down. Selection is uniform across the Items in scope, so adding "Pizza" twice doubles its odds: **repetition is the user's own weighting mechanism**, and the schema's `weight` column stays unread (ADR-0003) because the feature already exists in the simplest possible form. It is also the only enforceable answer — ADR-0002 permits no `UNIQUE` constraint outside the primary key, so a uniqueness rule could not survive two devices editing offline, and an app-code check would be advisory only.

The same reasoning runs through the Combine tab: a Combo's pool is the union of its member Lists' Items, and the same text in two member Lists is two entries and two chances. Deduplicating there would contradict the single-List behaviour and require the normalisation rule just rejected.

## Consequences

Duplicate Items are what make **provenance load-bearing**: a Combo's result names the source List, because "Pizza" from Lunch and "Pizza" from Dinner are otherwise indistinguishable (ADR-0017 carries this into the VoiceOver announcement, ADR-0022 into the string catalogue).

Selection stays uniform over Items, never over member Lists first. Picking a List and then an Item within it was rejected: it is a second selection concept, and it breaks the rule above. A 100-item List therefore dominates a 3-item one in a Combo they share, which is correct rather than unfair.

*Membership* is the one place deduplication does happen — `ComboList` rows are deduplicated by `listID` when the pool is built, because two devices adding the same List offline can produce duplicate rows and left alone that would silently double the List's weight.
