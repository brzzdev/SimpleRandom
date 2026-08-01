//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Foundation
public import SQLiteData

/// A named set of Lists whose Items are pooled and drawn from together.
///
/// A Combo references its member Lists by id through ``ComboList`` rather than copying
/// them, so it stays live as those Lists gain, lose and rename their Items.
///
/// Deliberately the same shape as ``List``, reserved columns included: one vocabulary
/// covers both tabs.
@Table
public struct Combo: Hashable, Identifiable, Sendable {
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
		name: String = "",
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
