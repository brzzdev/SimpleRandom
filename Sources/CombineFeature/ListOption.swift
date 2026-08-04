//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Models
public import SQLiteData

/// One row of the Combo form's membership checklist: a List, and the count its caption is
/// made of.
///
/// Only the Item count, never that List's own deck state: a Combo pools every Item of every
/// member regardless of what the List has dealt, so `Deck · 2 of 5 left` here would promise
/// the Combo respects it (ADR-0007). Counts only, in Combine, everywhere.
///
/// This is why `CombineFeature` does not depend on `ListsFeature` for a Lists query — the
/// checklist reads `Models.List` through its own `@FetchAll`, and it wants a different
/// selection from the one the Lists index renders.
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
		Models.List
			.group(by: \.id)
			.order { ($0.createdAt, $0.id) }
			.leftJoin(Item.all) { $0.id.eq($1.listID) }
			.select { list, item in
				Columns(itemCount: item.id.count(), list: list)
			}
	}
}
