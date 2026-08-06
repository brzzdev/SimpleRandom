//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Foundation
public import SQLiteData

/// A single candidate within a List. Text and nothing else: the app's job is picking one at
/// random, and every additional field is something to design, sync, and render on the
/// result sheet.
///
/// An Item belongs to exactly one List, which is what lets ``ListDraw`` key a draw on the
/// Item's own id.
///
/// `deletedAt`, `position`, `updatedAt` and `weight` are reserved and read by nothing in v1
/// (ADR-0003). `weight` in particular is not the selection mechanism: adding the same text
/// twice is, because selection is uniform over the Items in scope.
@Table
public struct Item: Hashable, Identifiable, Sendable {
	public let id: UUID
	public var createdAt: Date
	public var deletedAt: Date?
	public var listID: List.ID
	public var position: Int?
	public var title: String
	public var updatedAt: Date?
	public var weight: Int?

	public init(
		id: UUID,
		createdAt: Date,
		deletedAt: Date? = nil,
		listID: List.ID,
		position: Int? = nil,
		title: String,
		updatedAt: Date? = nil,
		weight: Int? = nil,
	) {
		self.id = id
		self.createdAt = createdAt
		self.deletedAt = deletedAt
		self.listID = listID
		self.position = position
		self.title = title
		self.updatedAt = updatedAt
		self.weight = weight
	}
}

extension Item {
	/// Every Item of every member List of one Combo — a Combo's whole pool, in no particular
	/// order.
	///
	/// **Membership is deduplicated by `listID`; the Items are not.** `IN` over the
	/// membership's `listID`s does the first: no `UNIQUE` is available outside the primary
	/// key, so two devices adding the same List offline leave two ``ComboList`` rows, and a
	/// join would pool that List's Items twice and silently double its weight (ADR-0008). The
	/// same text in two *different* member Lists stays two entries and two chances, exactly as
	/// within one List (ADR-0004).
	///
	/// Member Lists' own ``drawMode`` and ``ListDraw`` rows are not consulted here or
	/// anywhere else on this path: a Combo pools every Item of every member, including ones
	/// already dealt within their own List (ADR-0007).
	public static func inCombo(_ comboID: Combo.ID) -> Where<Item> {
		Self.where { $0.listID.in(ComboList.inCombo(comboID).select { $0.listID }) }
	}

	/// The Items of one List, in no particular order — the whole of what a plain List draws
	/// over, and where every other scoped query starts.
	public static func inList(_ listID: List.ID) -> Where<Item> {
		Self.where { $0.listID.eq(listID) }
	}

	/// The Items of one List that have no ``ListDraw`` row — everything a Deck has left to
	/// deal.
	///
	/// A Deck draws only over these, and the row it inserts takes the Item it dealt back out
	/// again: the pool shrinks by one on every draw, and a Deck is **exhausted** when nothing
	/// answers this query (ADR-0006). For a plain List it is the whole List, because nothing
	/// writes a draw row there.
	///
	/// The subquery needs no scoping of its own: an Item belongs to exactly one List, so a
	/// draw row belonging to another List's Item can never name an id this one's `WHERE`
	/// has let through.
	///
	/// Unordered, because the two callers want different things of it — the sheet's pool is
	/// `(createdAt, id)` like everything else, and a count is not ordered at all.
	public static func undealt(in listID: List.ID) -> Where<Item> {
		inList(listID) + Self.where { $0.id.notIn(ListDraw.all.select { $0.itemID }) }
	}

	/// The pooled Items of one Combo that have no ``ComboDraw`` row *for that Combo* —
	/// everything a Combo Deck has left to deal.
	///
	/// The same mechanism as ``undealt(in:)``, in a second table: the row's existence is the
	/// draw, the pool shrinks by one on every deal, and the Deck is **exhausted** when nothing
	/// answers this (ADR-0006).
	///
	/// **The subquery is scoped, and has to be**, which is the one thing that differs. An
	/// Item belongs to exactly one List, so a `ListDraw` row can only ever name an Item its
	/// List's `WHERE` has already let through; an Item belongs to any number of Combos, so an
	/// unscoped subquery here would let one Combo's deal empty another's deck.
	///
	/// Member Lists' own `drawMode` and `ListDraw` rows are not consulted, exactly as in
	/// ``inCombo(_:)``: an Item already dealt within its own List is still in this pool
	/// (ADR-0007).
	public static func undealt(inCombo comboID: Combo.ID) -> Where<Item> {
		inCombo(comboID) + Self.where { $0.id.notIn(ComboDraw.inCombo(comboID).select { $0.itemID }) }
	}
}

/// The macro generates `Draft` without carrying the conformances declared above, and every
/// one of its fields is `Sendable` already. Features build a draft on the main actor and
/// hand it to a database write, so this is the conformance that lets one cross.
extension Item.Draft: Sendable {}

extension Item.Draft {
	/// An Item that has not been saved yet.
	///
	/// The generated memberwise initialiser is internal to this target, so this is what the
	/// feature targets build a new Item with. It takes only the title a creating user supplies,
	/// the List it belongs to and the sort key, and leaves `id` `nil` so the schema's `newID()`
	/// default mints it — no insert site in the app names an id (ADR-0011).
	public init(createdAt: Date, listID: List.ID, title: String) {
		// Every argument is spelled out, `nil`s included, so this cannot resolve to itself.
		self.init(
			id: nil,
			createdAt: createdAt,
			deletedAt: nil,
			listID: listID,
			position: nil,
			title: title,
			updatedAt: nil,
			weight: nil,
		)
	}
}
