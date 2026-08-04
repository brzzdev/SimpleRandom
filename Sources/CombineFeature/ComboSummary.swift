//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Models
public import SQLiteData

/// One row of the Combine index: a Combo, and the three counts its caption is made of.
///
/// The counts are selected alongside the Combo rather than fetched per row, because the
/// index renders `3 Lists · 12 items` and `3 Lists · Deck · 10 of 13 left` for every Combo
/// on screen — a query per row is the same work spread over N round trips.
@Selection
public struct ComboSummary: Hashable, Identifiable, Sendable {
	public let combo: Combo
	public let dealtCount: Int
	public let itemCount: Int
	public let listCount: Int

	public var id: Combo.ID { combo.id }

	/// How many pooled Items a Combo Deck has left to deal. Meaningless for a plain Combo,
	/// which has no memory of what it has drawn.
	public var remainingCount: Int { itemCount - dealtCount }
}

extension ComboSummary {
	/// Every Combo, newest last, with its counts.
	///
	/// `(createdAt, id)` ascending is the app's one sort order. `createdAt` alone is not a
	/// total order — two devices creating rows offline in the same second leave SQLite to
	/// break the tie however it likes — and the primary key tie-break is arbitrary but
	/// identical on every device.
	///
	/// **Every count is `DISTINCT`, and that is the deduplication the domain requires rather
	/// than a defence against the join's fan-out.** No `UNIQUE` is available outside a
	/// primary key, so two devices adding the same List offline leave two `ComboList` rows
	/// for it; counting the join's rows would then double that List's Items and silently
	/// double its weight (ADR-0008). Counting distinct `items.id` collapses them, because an
	/// Item belongs to exactly one List — deduplicating by `listID` and deduplicating the
	/// Items it contributes are the same operation here.
	///
	/// The draw join is conditioned on the Item as well as the Combo, so `dealtCount` counts
	/// only draws of Items still in the pool. A List dropped from a Combo takes its draws out
	/// of the arithmetic with it, rather than leaving a Deck reading `-2 of 5 left`.
	public static var index: some Statement<ComboSummary> {
		Combo
			.group(by: \.id)
			.order { ($0.createdAt, $0.id) }
			.leftJoin(ComboList.all) { $0.id.eq($1.comboID) }
			.leftJoin(Item.all) { $1.listID.eq($2.listID) }
			.leftJoin(ComboDraw.all) { $0.id.eq($3.comboID) && $2.id.eq($3.itemID) }
			.select { combo, membership, item, draw in
				Columns(
					combo: combo,
					dealtCount: draw.itemID.count(distinct: true),
					itemCount: item.id.count(distinct: true),
					listCount: membership.listID.count(distinct: true),
				)
			}
	}
}
