//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Foundation
public import SQLiteData

/// One row per Item a Combo has dealt. **The row's existence is the draw**, exactly as in
/// ``ListDraw`` — the two decks are one mechanism, not two (ADR-0006).
///
/// A Combo's deck state needs both ids, because an Item can belong to many Combos. That is
/// also why this table could never be shared: records with multiple foreign keys are
/// excluded by the sync layer, and a Combo is a personal arrangement of your own Lists.
///
/// `deletedAt` is deliberately **not** reserved here, for the same reason it is absent from
/// ``ListDraw``.
@Table
public struct ComboDraw: Hashable, Identifiable, Sendable {
	public let id: UUID
	public var comboID: Combo.ID
	public var createdAt: Date
	public var itemID: Item.ID
	public var position: Int?
	public var updatedAt: Date?

	public init(
		id: UUID,
		comboID: Combo.ID,
		createdAt: Date,
		itemID: Item.ID,
		position: Int? = nil,
		updatedAt: Date? = nil,
	) {
		self.id = id
		self.comboID = comboID
		self.createdAt = createdAt
		self.itemID = itemID
		self.position = position
		self.updatedAt = updatedAt
	}
}

/// The macro generates `Draft` without carrying the conformances declared above, and every
/// one of its fields is `Sendable` already. The sheet builds a draft on the main actor and
/// hands it to a database write, so this is the conformance that lets one cross.
extension ComboDraw.Draft: Sendable {}

extension ComboDraw.Draft {
	/// A deal that has not been recorded yet.
	///
	/// The generated memberwise initialiser is internal to this target, so this is what the
	/// randomise sheet records a Combo Deck's deal with. It leaves `id` `nil` so the schema's
	/// `newID()` default mints it — no insert site in the app names an id (ADR-0011). ``ListDraw``
	/// needs no equivalent, because its primary key is the Item's own id.
	public init(comboID: Combo.ID, createdAt: Date, itemID: Item.ID) {
		// Every argument is spelled out, `nil`s included, so this cannot resolve to itself.
		self.init(
			id: nil,
			comboID: comboID,
			createdAt: createdAt,
			itemID: itemID,
			position: nil,
			updatedAt: nil,
		)
	}
}

extension ComboDraw {
	/// Every draw row belonging to one Combo — what it has dealt, and exactly what Reshuffle
	/// deletes.
	///
	/// A hard delete, and the whole of it, exactly as ``ListDraw/inList(_:)`` is: Reshuffle is
	/// not a soft delete and not a partial one (ADR-0003). It is the Combo's own rows and no
	/// others — a member List's ``ListDraw`` rows are not reached from here, or from anywhere
	/// (ADR-0007).
	///
	/// **Including rows for Items no longer in the pool.** Reshuffle puts the whole deck back,
	/// so leaving a stale row behind would mean an Item returning to the pool later — its List
	/// re-added to the Combo — arriving already dealt.
	public static func inCombo(_ comboID: Combo.ID) -> Where<ComboDraw> {
		Self.where { $0.comboID.eq(comboID) }
	}

	/// One Combo's draws of the Items belonging to particular Lists — what leaves with a member
	/// List when the form unticks it.
	///
	/// **Scoped by the Combo as well as by the Lists, and it has to be.** An Item belongs to any
	/// number of Combos, so a delete keyed on the Items alone would clear every other Combo's
	/// memory of them too — the failure ADR-0007 exists to rule out, arriving through the form
	/// instead of through the draw.
	public static func inCombo(
		_ comboID: Combo.ID,
		ofLists listIDs: [List.ID],
	) -> Where<ComboDraw> {
		inCombo(comboID)
			+ Self.where { $0.itemID.in(Item.where { $0.listID.in(listIDs) }.select { $0.id }) }
	}

	/// One Combo's draws of Items that are still in its pool — the rows its arithmetic counts.
	///
	/// Narrower than ``inCombo(_:)`` because a Combo can hold draws of Items it no longer pools,
	/// and counting those would read the Deck down below zero.
	///
	/// **This survives ``inCombo(_:ofLists:)``, which looks to make it redundant.** That cleanup
	/// runs on the device doing the unticking; a second device unticking offline deletes the
	/// `ComboList` row and nothing tells this one to clear the draws. ADR-0008's premise is that
	/// concurrent offline edits are a legal steady state rather than a corrupt one, so a cleanup
	/// on one device can never be the arithmetic's guarantee. It is the same condition
	/// `ComboSummary.index` joins on, said of one Combo.
	public static func pooled(in comboID: Combo.ID) -> Where<ComboDraw> {
		inCombo(comboID) + Self.where { $0.itemID.in(Item.inCombo(comboID).select { $0.id }) }
	}
}
