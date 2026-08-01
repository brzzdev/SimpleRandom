//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SQLiteData

/// The live database, opened in the app container and migrated to the current schema.
///
/// Called once from `SimpleRandomApp`'s `prepareDependencies`, before any feature can reach
/// for `@Dependency(\.defaultDatabase)`.
///
/// The sync layer's metadata database is deliberately **not** attached: there is no per-row
/// "not yet synced" badge to bind to, and attaching it would invite explaining sync at a
/// granularity the rest of the app avoids.
public func appDatabase() throws -> any DatabaseWriter {
	var configuration = Configuration()
	// Spelled out rather than left to GRDB's default, because every cascade in this schema
	// — and so every rule `DatabaseTests` asserts — depends on it.
	configuration.foreignKeysEnabled = true
	configuration.prepareDatabase { db in
		db.add(function: $uuidV7)
	}

	let database = try SQLiteData.defaultDatabase(configuration: configuration)
	try migrator.migrate(database)
	return database
}

/// A fresh, empty database held in memory, built by the real ``migrator``.
///
/// This is what `DatabaseTests` runs against, one per test case. A hand-written test schema
/// would forfeit the entire reason those tests exist, and a repository client mocked in
/// front of this would only add drift (ADR-0019).
public func inMemory() throws -> any DatabaseWriter {
	var configuration = Configuration()
	configuration.foreignKeysEnabled = true
	configuration.prepareDatabase { db in
		db.add(function: $countingID)
	}

	let database = try DatabaseQueue(configuration: configuration)
	try migrator.migrate(database)
	return database
}
