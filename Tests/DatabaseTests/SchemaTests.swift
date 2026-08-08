//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import CustomDump
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
		@Test
		func theSchemaHoldsExactlyTheSixTablesTheDomainModelDeclares() async throws {
			@Dependency(\.defaultDatabase) var database

			let tables = try await database.read { db in
				try #sql(
					"""
					SELECT "name" FROM sqlite_schema
					WHERE "type" = 'table' AND "name" NOT LIKE 'sqlite\\_%' ESCAPE '\\'
					AND "name" <> 'grdb_migrations'
					ORDER BY "name"
					""",
					as: String.self
				)
				.fetchAll(db)
			}

			// Every other test here is parameterised over `TableShape.all`, so without this
			// one a seventh table would be added to the migrator and asserted about by
			// nothing — which is precisely the append-only mistake this suite exists to catch.
			expectNoDifference(tables, TableShape.all.map(\.name))
		}

		@Test(arguments: TableShape.all)
		func tableHasExactlyTheColumnsTheDomainModelDeclares(shape: TableShape) async throws {
			@Dependency(\.defaultDatabase) var database

			let columns = try await database.read { db in
				try #sql(
					"""
					SELECT "name", "type", "notnull", "dflt_value"
					FROM pragma_table_info(\(bind: shape.name)) ORDER BY "name"
					""",
					as: ColumnDefinition.self
				)
				.fetchAll(db)
			}

			// The whole definition, not just the name: under an append-only schema a column's
			// affinity, its nullability and its default are as permanent as its existence, and
			// a missing `newID()` default would leave a table minting no ids at all.
			expectNoDifference(columns, shape.columns)
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
			expectNoDifference(primaryKey, [PrimaryKeyColumn(name: shape.primaryKeyColumn, type: "TEXT")])
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
			expectNoDifference(Set(foreignKeys), shape.foreignKeys)
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

			try await database.write { db in
				try Models.List
					.insert { ($0.createdAt, $0.name) } values: {
						(.seed, "Lunch")
						(.seed, "Films")
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
			expectNoDifference(Set(lists.map(\.id)).count, 2)
			// And the mode a List is born in, which the editor sheet may leave alone.
			#expect(lists.allSatisfy { $0.drawMode == .independent })
		}
	}
}

/// One table's declared shape — the `CONTEXT.md` tables, written out so the migrator can be
/// held to them.
struct TableShape: Sendable {
	let columns: [ColumnDefinition]
	let foreignKeys: Set<ForeignKey>
	let name: String
	let primaryKeyColumn: String

	/// All six, in the order `sqlite_schema` lists them.
	static let all: [Self] = [
		Self(
			columns: [
				.required("comboID"),
				.required("createdAt"),
				.required("id", default: "newID()"),
				.required("itemID"),
				.optional("position", "INTEGER"),
				.optional("updatedAt"),
			],
			foreignKeys: [
				ForeignKey(from: "comboID", table: "combos", onDelete: "CASCADE"),
				ForeignKey(from: "itemID", table: "items", onDelete: "CASCADE"),
			],
			name: "comboDraws",
			primaryKeyColumn: "id",
		),
		Self(
			columns: [
				.required("comboID"),
				.required("createdAt"),
				.optional("deletedAt"),
				.required("id", default: "newID()"),
				.required("listID"),
				.optional("position", "INTEGER"),
				.optional("updatedAt"),
			],
			foreignKeys: [
				ForeignKey(from: "comboID", table: "combos", onDelete: "CASCADE"),
				ForeignKey(from: "listID", table: "lists", onDelete: "CASCADE"),
			],
			name: "comboLists",
			primaryKeyColumn: "id",
		),
		Self(
			columns: [
				.required("createdAt"),
				.optional("deletedAt"),
				.required("drawMode", default: "'independent'"),
				.optional("emoji"),
				.required("id", default: "newID()"),
				.required("name"),
				.optional("position", "INTEGER"),
				.optional("updatedAt"),
			],
			foreignKeys: [],
			name: "combos",
			primaryKeyColumn: "id",
		),
		Self(
			columns: [
				.required("createdAt"),
				.optional("deletedAt"),
				.required("id", default: "newID()"),
				.required("listID"),
				.optional("position", "INTEGER"),
				.required("title"),
				.optional("updatedAt"),
				.optional("weight", "INTEGER"),
			],
			foreignKeys: [ForeignKey(from: "listID", table: "lists", onDelete: "CASCADE")],
			name: "items",
			primaryKeyColumn: "id",
		),
		// The primary key *is* the foreign key, which is both what an Item's single owner
		// makes possible and what a `privateTables` side table requires. No `deletedAt`: the
		// only deletion here is Reshuffle, and a soft delete would break the arithmetic that
		// decides whether a Deck is exhausted.
		Self(
			columns: [
				.required("createdAt"),
				.required("itemID"),
				.optional("position", "INTEGER"),
				.optional("updatedAt"),
			],
			foreignKeys: [ForeignKey(from: "itemID", table: "items", onDelete: "CASCADE")],
			name: "listDraws",
			primaryKeyColumn: "itemID",
		),
		// No foreign keys at all, which is what makes a List the one valid share root should
		// `CKShare` ever arrive.
		Self(
			columns: [
				.required("createdAt"),
				.optional("deletedAt"),
				.required("drawMode", default: "'independent'"),
				.optional("emoji"),
				.required("id", default: "newID()"),
				.required("name"),
				.optional("position", "INTEGER"),
				.optional("updatedAt"),
			],
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

/// One column exactly as `pragma_table_info` reports it. Property order is that pragma's
/// column order, not alphabetical: `#sql` decodes a `@Selection` positionally.
@Selection
struct ColumnDefinition: Hashable, Sendable {
	let name: String
	let type: String
	let isNotNull: Bool
	let defaultValue: String?
}

extension ColumnDefinition {
	/// A column the domain requires a value for. `default:` is the SQL default expression as
	/// SQLite echoes it back, and its absence is the assertion for `name` and `title`: a
	/// `DEFAULT ''` would let an omitted one persist as a valid-looking empty string.
	static func required(_ name: String, _ type: String = "TEXT", default: String? = nil) -> Self {
		Self(name: name, type: type, isNotNull: true, defaultValue: `default`)
	}

	/// A column that may be `NULL` — in this schema, every reserved one (ADR-0003) and the
	/// optional emoji.
	static func optional(_ name: String, _ type: String = "TEXT") -> Self {
		Self(name: name, type: type, isNotNull: false, defaultValue: nil)
	}
}
