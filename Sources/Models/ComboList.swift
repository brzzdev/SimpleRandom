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
