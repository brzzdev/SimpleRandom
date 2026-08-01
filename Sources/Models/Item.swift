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
