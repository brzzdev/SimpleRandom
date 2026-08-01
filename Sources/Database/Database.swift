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
	let database = try SQLiteData.defaultDatabase(
		configuration: configuration(registering: { $0.add(function: $uuidV7) })
	)
	try migrator.migrate(database)
	return database
}

/// A fresh, empty database held in memory, built by the real ``migrator``.
///
/// This is what `DatabaseTests` runs against, one per test case. A hand-written test schema
/// would forfeit the entire reason those tests exist, and a repository client mocked in
/// front of this would only add drift (ADR-0019).
public func inMemory() throws -> any DatabaseWriter {
	let database = try DatabaseQueue(
		configuration: configuration(registering: { $0.add(function: $countingID) })
	)
	try migrator.migrate(database)
	return database
}

/// What the two databases share, which is everything but the generator answering to
/// `newID()` and the writer they are opened as.
///
/// `foreignKeysEnabled` is spelled out rather than left to GRDB's default, because every
/// cascade in this schema — and so every rule `DatabaseTests` asserts — depends on it, and a
/// library default is a poor place for a load-bearing fact to live.
private func configuration(
	registering idGenerator: @escaping @Sendable (Database) -> Void,
) -> Configuration {
	var configuration = Configuration()
	configuration.foreignKeysEnabled = true
	configuration.prepareDatabase(idGenerator)
	return configuration
}
