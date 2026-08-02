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
