//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Foundation
public import SQLiteData

/// One row per Item its List has dealt. **The row's existence is the draw** — there is no
/// flag to read and nothing to unset, and Reshuffle deletes the rows (ADR-0006).
///
/// An Item belongs to exactly one List, so the Item's own id identifies the draw and no
/// separate `id` or `listID` is needed. Foreign-key-as-primary-key is also the shape a
/// `privateTables` side table must take, and this one is declared private from day one:
/// deck state is written on every tap, so moving it after ship would be a live data
/// migration rather than the dead column a never-written reserved column leaves behind.
///
/// `deletedAt` is deliberately **not** reserved here. The only deletion is Reshuffle, which
/// is designed as a hard delete, and a soft-delete column would quietly break the
/// arithmetic that decides whether a Deck is exhausted (ADR-0003).
@Table
public struct ListDraw: Hashable, Identifiable, Sendable {
	@Column(primaryKey: true)
	public let itemID: Item.ID
	public var createdAt: Date
	public var position: Int?
	public var updatedAt: Date?

	public var id: Item.ID { itemID }

	public init(
		itemID: Item.ID,
		createdAt: Date,
		position: Int? = nil,
		updatedAt: Date? = nil,
	) {
		self.itemID = itemID
		self.createdAt = createdAt
		self.position = position
		self.updatedAt = updatedAt
	}
}

extension ListDraw {
	/// Every draw row belonging to one List's Items — what that List has dealt, and exactly
	/// what Reshuffle deletes.
	///
	/// A hard delete, and the whole of it: Reshuffle is not a soft delete and not a partial
	/// one, which is why ``deletedAt`` is not reserved on this table (ADR-0003). The rows
	/// are reached through the Items because a draw is keyed on the Item alone — a List
	/// cannot be named without going through them.
	public static func inList(_ listID: List.ID) -> Where<ListDraw> {
		Self.where { $0.itemID.in(Item.inList(listID).select { $0.id }) }
	}
}
