//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import Database
internal import DependenciesTestSupport
internal import Foundation
internal import SQLiteData
internal import Testing

/// The base suite every test here nests inside, and the only place a database is made.
///
/// The trait is applied once, at suite level, but its scope is provided **per test case**,
/// so each test gets a fresh in-memory database — built by the real `migrator`, because a
/// hand-written test schema would forfeit the entire reason this target exists: the sync
/// layer enforces its constraints at runtime, so the schema itself needs assertions
/// (ADR-0019).
///
/// Worlds are seeded inline, per case. There is no shared fixture: these tests need small
/// specific worlds that do not share a seed, and a fixture makes tests read as assertions
/// about `seedSampleData()` rather than about the domain.
@Suite(.dependency(\.defaultDatabase, try inMemory()))
internal struct DatabaseTests {}

extension Date {
	/// The one timestamp every seeded row in this target carries. Nothing here asserts on
	/// ordering, and a fixed instant keeps the seeded worlds about their shape.
	internal static let seed = Date(timeIntervalSince1970: 1_234_567_890)
}
