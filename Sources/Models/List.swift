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
