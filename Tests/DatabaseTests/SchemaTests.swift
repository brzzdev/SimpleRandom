//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import Foundation
internal import Models
internal import SQLiteData
internal import Testing

extension DatabaseTests {
	/// The shape of the schema itself, asserted rather than assumed.
	///
	/// The sync layer checks these rules when `SyncEngine` is constructed — at runtime, on a
	/// device, with a CloudKit container. Nothing here can wait for that: the CloudKit schema
	/// is append-only from the first shipped build, so a column in the wrong place is
	/// permanent (ADR-0002).
	@Suite
	struct SchemaTests {
		@Test(arguments: TableShape.all)
		func tableHasExactlyTheColumnsTheDomainModelDeclares(shape: TableShape) async throws {
			@Dependency(\.defaultDatabase) var database

			let columns = try await database.read { db in
				try #sql(
					"""
					SELECT "name" FROM pragma_table_info(\(bind: shape.name)) ORDER BY "name"
					""",
					as: String.self
				)
				.fetchAll(db)
			}

			#expect(columns == shape.columns)
		}

		@Test(arguments: TableShape.all)
		func tablesPrimaryKeyIsOneTextColumn(shape: TableShape) async throws {
			@Dependency(\.defaultDatabase) var database

			let primaryKey = try await database.read { db in
				try #sql(
					"""
					SELECT "name", "type" FROM pragma_table_info(\(bind: shape.name)) WHERE "pk" > 0
					""",
					as: PrimaryKeyColumn.self
				)
				.fetchAll(db)
			}

			// One column, never a compound key, and `TEXT` because it holds a `UUID`. An
			// `AUTOINCREMENT` integer would let two devices both mint `id: 1`.
			#expect(primaryKey == [PrimaryKeyColumn(name: shape.primaryKeyColumn, type: "TEXT")])
		}

		@Test(arguments: TableShape.all)
		func tablesForeignKeysAllCascadeOnDelete(shape: TableShape) async throws {
			@Dependency(\.defaultDatabase) var database

			let foreignKeys = try await database.read { db in
				try #sql(
					"""
					SELECT "from", "table", "on_delete" FROM pragma_foreign_key_list(\(bind: shape.name))
					""",
					as: ForeignKey.self
				)
				.fetchAll(db)
			}

			// Every expectation below spells `CASCADE`, which is the assertion: SQLite's
			// implicit `NO ACTION` is rejected by the sync layer, and `SET NULL` and
			// `SET DEFAULT` would leave rows this domain has no meaning for.
			#expect(Set(foreignKeys) == shape.foreignKeys)
		}

		@Test(arguments: TableShape.all)
		func tableHasNoUniqueConstraintOutsideItsPrimaryKey(shape: TableShape) async throws {
			@Dependency(\.defaultDatabase) var database

			let uniqueIndexes = try await database.read { db in
				try #sql(
					"""
					SELECT "name" FROM pragma_index_list(\(bind: shape.name))
					WHERE "unique" = 1 AND "origin" <> 'pk'
					""",
					as: String.self
				)
				.fetchAll(db)
			}

			// Uniqueness is unenforceable here and deliberately absent (ADR-0004): two Items
			// in a List may share a title, because repetition is the user's own weighting.
			#expect(uniqueIndexes.isEmpty)
		}

		@Test
		func insertingWithoutAnIDTakesOneFromTheSchemasDefault() async throws {
			@Dependency(\.defaultDatabase) var database

			let createdAt = Date(timeIntervalSince1970: 1_234_567_890)

			try await database.write { db in
				try Models.List
					.insert { ($0.createdAt, $0.name) } values: {
						(createdAt, "Lunch")
						(createdAt, "Films")
					}
					.execute(db)
			}

			let lists = try await database.read { db in
				try Models.List.all.fetchAll(db)
			}

			// No insert site anywhere in the app mentions an id, so none can forget one. The
			// column's default is a generator registered on the connection — and the ids it
			// mints are distinct, which is the whole requirement a distributed schema places
			// on them.
			#expect(Set(lists.map(\.id)).count == 2)
			// And the mode a List is born in, which the editor sheet may leave alone.
			#expect(lists.allSatisfy { $0.drawMode == .independent })
		}
	}
}

/// One table's declared shape — the `CONTEXT.md` tables, written out so the migrator can be
/// held to them.
struct TableShape: Sendable {
	let columns: [String]
	let foreignKeys: Set<ForeignKey>
	let name: String
	let primaryKeyColumn: String

	/// All six, and the fact that there are six.
	static let all: [Self] = [
		Self(
			columns: ["comboID", "createdAt", "id", "itemID", "position", "updatedAt"],
			foreignKeys: [
				ForeignKey(from: "comboID", table: "combos", onDelete: "CASCADE"),
				ForeignKey(from: "itemID", table: "items", onDelete: "CASCADE"),
			],
			name: "comboDraws",
			primaryKeyColumn: "id",
		),
		Self(
			columns: ["comboID", "createdAt", "deletedAt", "id", "listID", "position", "updatedAt"],
			foreignKeys: [
				ForeignKey(from: "comboID", table: "combos", onDelete: "CASCADE"),
				ForeignKey(from: "listID", table: "lists", onDelete: "CASCADE"),
			],
			name: "comboLists",
			primaryKeyColumn: "id",
		),
		Self(
			columns: ["createdAt", "deletedAt", "drawMode", "emoji", "id", "name", "position", "updatedAt"],
			foreignKeys: [],
			name: "combos",
			primaryKeyColumn: "id",
		),
		Self(
			columns: ["createdAt", "deletedAt", "id", "listID", "position", "title", "updatedAt", "weight"],
			foreignKeys: [ForeignKey(from: "listID", table: "lists", onDelete: "CASCADE")],
			name: "items",
			primaryKeyColumn: "id",
		),
		// The primary key *is* the foreign key, which is both what an Item's single owner
		// makes possible and what a `privateTables` side table requires. No `deletedAt`: the
		// only deletion here is Reshuffle, and a soft delete would break the arithmetic that
		// decides whether a Deck is exhausted.
		Self(
			columns: ["createdAt", "itemID", "position", "updatedAt"],
			foreignKeys: [ForeignKey(from: "itemID", table: "items", onDelete: "CASCADE")],
			name: "listDraws",
			primaryKeyColumn: "itemID",
		),
		// No foreign keys at all, which is what makes a List the one valid share root should
		// `CKShare` ever arrive.
		Self(
			columns: ["createdAt", "deletedAt", "drawMode", "emoji", "id", "name", "position", "updatedAt"],
			foreignKeys: [],
			name: "lists",
			primaryKeyColumn: "id",
		),
	]
}

/// Property order here is `pragma_foreign_key_list`'s column order, not alphabetical:
/// `#sql` decodes a `@Selection` positionally.
@Selection
struct ForeignKey: Hashable, Sendable {
	let from: String
	let table: String
	let onDelete: String
}

@Selection
struct PrimaryKeyColumn: Hashable, Sendable {
	let name: String
	let type: String
}
