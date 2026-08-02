//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SQLiteData

/// The one migrator, used by `appDatabase()` and by `inMemory()` alike.
///
/// Tests run against this rather than a hand-written test schema, which is the whole reason
/// `DatabaseTests` can say anything about the real database: the sync layer enforces its
/// constraints at runtime, so a schema built twice is a schema asserted about once
/// (ADR-0019).
///
/// There is no `eraseDatabaseOnSchemaChange`, deliberately. Under a synced schema, erasing
/// local data does not erase CloudKit's — the device simply re-downloads it on the next
/// launch — so the erase is ineffective where it looks most reassuring, and it hides
/// exactly the append-only mistakes (ADR-0002) that must be caught before the first shipped
/// build.
public var migrator: DatabaseMigrator {
	var migrator = DatabaseMigrator()

	// Registered in dependency order — a table's parents exist before its foreign keys
	// reference them. Every foreign key carries an explicit `ON DELETE`, and every one of
	// them is `CASCADE`: the sync layer rejects SQLite's implicit `NO ACTION` outright.
	//
	// Every primary key is a `UUID` defaulted by `newID()`, spelled `NOT NULL ON CONFLICT
	// REPLACE` so that inserting a `NULL` id substitutes the default rather than failing.
	// No `UNIQUE` appears outside a primary key, because two devices editing offline could
	// never honour one (ADR-0004).
	//
	// `name` and `title` carry no default, unlike `drawMode`. `CONTEXT.md` calls both
	// trimmed and non-empty, and a `DEFAULT ''` would let an omitted one persist as a
	// valid-looking empty string on every device; without it the same mistake fails at the
	// insert. `.independent` is a real domain default rather than a stand-in for a missing
	// value, so it keeps its.
	migrator.registerMigration("Create the v1 schema") { db in
		try #sql(
			"""
			CREATE TABLE "lists" (
			  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (newID()),
			  "createdAt" TEXT NOT NULL,
			  "deletedAt" TEXT,
			  "drawMode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'independent',
			  "emoji" TEXT,
			  "name" TEXT NOT NULL,
			  "position" INTEGER,
			  "updatedAt" TEXT
			) STRICT
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE TABLE "items" (
			  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (newID()),
			  "createdAt" TEXT NOT NULL,
			  "deletedAt" TEXT,
			  "listID" TEXT NOT NULL REFERENCES "lists"("id") ON DELETE CASCADE,
			  "position" INTEGER,
			  "title" TEXT NOT NULL,
			  "updatedAt" TEXT,
			  "weight" INTEGER
			) STRICT
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE INDEX "index_items_on_listID" ON "items"("listID")
			"""
		)
		.execute(db)

		// The primary key *is* the foreign key: an Item belongs to exactly one List, so its
		// own id identifies the draw. That is also the shape a `privateTables` side table
		// must take. No `deletedAt` — the only deletion here is Reshuffle, and it is hard.
		try #sql(
			"""
			CREATE TABLE "listDraws" (
			  "itemID" TEXT PRIMARY KEY NOT NULL REFERENCES "items"("id") ON DELETE CASCADE,
			  "createdAt" TEXT NOT NULL,
			  "position" INTEGER,
			  "updatedAt" TEXT
			) STRICT
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE TABLE "combos" (
			  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (newID()),
			  "createdAt" TEXT NOT NULL,
			  "deletedAt" TEXT,
			  "drawMode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'independent',
			  "emoji" TEXT,
			  "name" TEXT NOT NULL,
			  "position" INTEGER,
			  "updatedAt" TEXT
			) STRICT
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE TABLE "comboLists" (
			  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (newID()),
			  "comboID" TEXT NOT NULL REFERENCES "combos"("id") ON DELETE CASCADE,
			  "createdAt" TEXT NOT NULL,
			  "deletedAt" TEXT,
			  "listID" TEXT NOT NULL REFERENCES "lists"("id") ON DELETE CASCADE,
			  "position" INTEGER,
			  "updatedAt" TEXT
			) STRICT
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE INDEX "index_comboLists_on_comboID" ON "comboLists"("comboID")
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE INDEX "index_comboLists_on_listID" ON "comboLists"("listID")
			"""
		)
		.execute(db)

		// Both ids, unlike `listDraws`: an Item can belong to many Combos, so the Item's id
		// alone would not say which Combo dealt it.
		try #sql(
			"""
			CREATE TABLE "comboDraws" (
			  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (newID()),
			  "comboID" TEXT NOT NULL REFERENCES "combos"("id") ON DELETE CASCADE,
			  "createdAt" TEXT NOT NULL,
			  "itemID" TEXT NOT NULL REFERENCES "items"("id") ON DELETE CASCADE,
			  "position" INTEGER,
			  "updatedAt" TEXT
			) STRICT
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE INDEX "index_comboDraws_on_comboID" ON "comboDraws"("comboID")
			"""
		)
		.execute(db)

		try #sql(
			"""
			CREATE INDEX "index_comboDraws_on_itemID" ON "comboDraws"("itemID")
			"""
		)
		.execute(db)
	}

	return migrator
}
