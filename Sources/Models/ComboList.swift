//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Foundation
public import SQLiteData

/// One row per membership — a List belonging to a Combo.
///
/// Membership is a join table rather than a `[UUID]` column on ``Combo`` because conflict
/// resolution is field-wise last-writer-wins: with an array, two devices each adding a
/// different List offline means one edit is silently lost, whereas rows merge (ADR-0008).
///
/// The surrogate `id` is what sync requires of a join table — every synchronised table
/// needs exactly one non-compound primary key — and no `UNIQUE` is available to stop two
/// devices adding the same List offline, so the pool deduplicates by `listID` when it is
/// built.
@Table
public struct ComboList: Hashable, Identifiable, Sendable {
	public let id: UUID
	public var comboID: Combo.ID
	public var createdAt: Date
	public var deletedAt: Date?
	public var listID: List.ID
	public var position: Int?
	public var updatedAt: Date?

	public init(
		id: UUID,
		comboID: Combo.ID,
		createdAt: Date,
		deletedAt: Date? = nil,
		listID: List.ID,
		position: Int? = nil,
		updatedAt: Date? = nil,
	) {
		self.id = id
		self.comboID = comboID
		self.createdAt = createdAt
		self.deletedAt = deletedAt
		self.listID = listID
		self.position = position
		self.updatedAt = updatedAt
	}
}

/// The macro generates `Draft` without carrying the conformances declared above, and every
/// one of its fields is `Sendable` already. Features build a draft on the main actor and
/// hand it to a database write, so this is the conformance that lets one cross.
extension ComboList.Draft: Sendable {}

extension ComboList.Draft {
	/// A membership that has not been saved yet.
	///
	/// The generated memberwise initialiser is internal to this target, so this is what the
	/// Combo form adds a member List with. It leaves `id` `nil` so the schema's `newID()`
	/// default mints it — no insert site in the app names an id (ADR-0011).
	public init(comboID: Combo.ID, createdAt: Date, listID: List.ID) {
		// Every argument is spelled out, `nil`s included, so this cannot resolve to itself.
		self.init(
			id: nil,
			comboID: comboID,
			createdAt: createdAt,
			deletedAt: nil,
			listID: listID,
			position: nil,
			updatedAt: nil,
		)
	}
}

extension ComboList {
	/// One Combo's memberships, in no particular order.
	///
	/// Unordered for the reason ``Item/inList(_:)`` is: the callers want different things of
	/// it, and a membership carries no order anything reads — `position` is reserved and
	/// unread in v1 (ADR-0003).
	public static func inCombo(_ comboID: Combo.ID) -> Where<ComboList> {
		Self.where { $0.comboID.eq(comboID) }
	}
}
