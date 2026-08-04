//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// Public because `Models.List.ID` aliases `Foundation.UUID`, and both `id` and
// ``inCombo(_:)``'s parameter are public. The `internal import SwiftUI` below is what makes
// it necessary: without it the alias resolved through SQLiteData's own public re-export.
public import Foundation
public import Models
public import SQLiteData

internal import SwiftUI

/// A List as the Combine tab renders one: the List, and the count its caption is made of.
///
/// **Both of Combine's List rows are this shape** — the form's membership checklist and
/// `ComboDetail`'s member rows — which is why they are one type rather than two identical
/// ones. `Accessibility` says the same thing from the other end: "Combo member, membership
/// picker" share a single row label, `Lunch, 4 items` (ADR-0018). ``all`` is the checklist and
/// ``inCombo(_:)`` is the member rows; the row itself is the same either way.
///
/// Only the Item count, never that List's own deck state: a Combo pools every Item of every
/// member regardless of what the List has dealt, so `Deck · 2 of 5 left` here would promise
/// the Combo respects it (ADR-0007). Counts only, in Combine, everywhere.
///
/// This is why `CombineFeature` does not depend on `ListsFeature` for a Lists query — these
/// rows read `Models.List` through their own `@FetchAll`, and they want a different selection
/// from the one the Lists index renders.
@Selection
public struct ListOption: Hashable, Identifiable, Sendable {
	public let itemCount: Int
	public let list: Models.List

	public var id: Models.List.ID { list.id }
}

extension ListOption {
	/// Every List, newest last, with its Item count.
	///
	/// Empty Lists are here rather than filtered out: they are shown and are selectable, and
	/// a List you are about to fill is a reasonable thing to add to a Combo (ADR-0020). The
	/// left join is what keeps them, counting zero rather than dropping the row.
	public static var all: some Statement<ListOption> {
		counted(Models.List.all)
	}

	/// One Combo's member Lists, newest last, with their Item counts.
	///
	/// Deduplicated by `listID` through ``Models/List/inCombo(_:)``, so a List two devices
	/// added offline is one row here rather than two — the same deduplication the pool applies
	/// (ADR-0008). Joining ``ComboList`` instead would have shown it twice and counted its
	/// Items twice in the caption above the button.
	public static func inCombo(_ comboID: Combo.ID) -> some Statement<ListOption> {
		counted(Models.List.inCombo(comboID))
	}

	/// Counts the Items of each of `lists`, newest last — the half both queries above share,
	/// so the two differ only in which Lists they are over.
	///
	/// `(createdAt, id)` ascending is the app's one sort order. `createdAt` alone is not a
	/// total order — two devices creating rows offline in the same second leave SQLite to
	/// break the tie however it likes — and the primary key tie-break is arbitrary but
	/// identical on every device.
	private static func counted(
		_ lists: Where<Models.List>,
	) -> some Statement<ListOption> {
		lists
			.group(by: \.id)
			.order { ($0.createdAt, $0.id) }
			.leftJoin(Item.all) { $0.id.eq($1.listID) }
			.select { list, item in
				Columns(itemCount: item.id.count(), list: list)
			}
	}
}

extension ListOption {
	/// What a row reads: `4 items`, or `No items`.
	///
	/// Beside the type rather than beside either renderer, because both of them render it —
	/// the form's checklist and `ComboDetail`'s member rows are one row shape, and a caption
	/// living in one view file would be reached from the other.
	///
	/// Empty Lists are shown and are selectable — there is no minimum, and a List you are
	/// about to fill is a reasonable thing to add (ADR-0020) — so the zero case is spelled
	/// out rather than left to inflect into "0 items".
	internal var caption: Text {
		itemCount == 0
			? Text("No items", bundle: #bundle)
			: Text("^[\(itemCount) items](inflect: true)", bundle: #bundle)
	}

	/// What VoiceOver reads: `Lunch, 4 items`, plus the **Selected** trait where a row can be
	/// ticked.
	///
	/// Authored separately from ``caption`` rather than derived from it, because the spoken
	/// separator is a comma and the name is inside the phrase rather than beside it.
	internal var accessibilityLabel: Text {
		itemCount == 0
			? Text("\(list.name), No items", bundle: #bundle)
			: Text("\(list.name), ^[\(itemCount) items](inflect: true)", bundle: #bundle)
	}
}
