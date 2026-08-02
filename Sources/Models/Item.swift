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
