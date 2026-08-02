//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Models
public import SQLiteData

/// One row of the Lists index: a List, and the two counts its caption is made of.
///
/// The counts are selected alongside the List rather than fetched per row, because the index
/// renders `N items` and `Deck · N of M left` for every List on screen — a query per row is
/// the same work spread over N round trips.
@Selection
public struct ListSummary: Hashable, Identifiable, Sendable {
	public let dealtCount: Int
	public let itemCount: Int
	public let list: Models.List

	public var id: Models.List.ID { list.id }

	/// How many Items a Deck has left to deal. Meaningless for a plain List, which has no
	/// memory of what it has drawn.
	public var remainingCount: Int { itemCount - dealtCount }
}

extension ListSummary {
	/// Every List, newest last, with its counts.
	///
	/// `(createdAt, id)` ascending is the app's one sort order. `createdAt` alone is not a
	/// total order — two devices creating rows offline in the same second leave SQLite to
	/// break the tie however it likes — and the primary key tie-break is arbitrary but
	/// identical on every device.
	///
	/// The second join cannot fan the row count out: `listDraws.itemID` is that table's
	/// primary key, so an Item has at most one draw row. That is what lets both counts come
	/// off one `GROUP BY` instead of a subquery each.
	public static var index: some Statement<ListSummary> {
		Models.List
			.group(by: \.id)
			.order { ($0.createdAt, $0.id) }
			.leftJoin(Item.all) { $0.id.eq($1.listID) }
			.leftJoin(ListDraw.all) { $1.id.eq($2.itemID) }
			.select { list, item, draw in
				Columns(
					dealtCount: draw.itemID.count(),
					itemCount: item.id.count(),
					list: list,
				)
			}
	}
}
