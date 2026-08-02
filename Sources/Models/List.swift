//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Foundation
public import SQLiteData

/// A named collection of Items, and the unit a randomise runs over.
///
/// The name collides with SwiftUI's `List`, and the domain word wins: feature views that
/// import SwiftUI qualify this as `Models.List`. A second vocabulary for the code was
/// rejected as a permanent translation cost paid to avoid an occasional qualification.
///
/// `deletedAt`, `position` and `updatedAt` are reserved and read by nothing in v1. The
/// CloudKit schema is append-only from the first shipped build, so reserving them is free
/// now and impossible later (ADR-0003).
@Table
public struct List: Hashable, Identifiable, Sendable {
	public let id: UUID
	public var createdAt: Date
	public var deletedAt: Date?
	public var drawMode: DrawMode
	public var emoji: String?
	public var name: String
	public var position: Int?
	public var updatedAt: Date?

	public init(
		id: UUID,
		createdAt: Date,
		deletedAt: Date? = nil,
		drawMode: DrawMode = .independent,
		emoji: String? = nil,
		name: String,
		position: Int? = nil,
		updatedAt: Date? = nil,
	) {
		self.id = id
		self.createdAt = createdAt
		self.deletedAt = deletedAt
		self.drawMode = drawMode
		self.emoji = emoji
		self.name = name
		self.position = position
		self.updatedAt = updatedAt
	}
}

/// The macro generates `Draft` without carrying the conformances declared above, and every
/// one of its fields is `Sendable` already. Features build a draft on the main actor and
/// hand it to a database write, so this is the conformance that lets one cross.
extension List.Draft: Sendable {}

extension List.Draft {
	/// A List that has not been saved yet.
	///
	/// The generated memberwise initialiser is internal to this target, so this is what the
	/// feature targets build a new List with. It takes only the two fields a creating user
	/// supplies plus the sort key, and leaves `id` `nil` so the schema's `newID()` default
	/// mints it — no insert site in the app names an id (ADR-0011).
	public init(
		createdAt: Date,
		drawMode: DrawMode = .independent,
		emoji: String? = nil,
		name: String,
	) {
		// Every argument is spelled out, `nil`s included, so this cannot resolve to itself.
		self.init(
			id: nil,
			createdAt: createdAt,
			deletedAt: nil,
			drawMode: drawMode,
			emoji: emoji,
			name: name,
			position: nil,
			updatedAt: nil,
		)
	}
}
