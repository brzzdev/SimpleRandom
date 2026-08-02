//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import Database
internal import Dependencies
internal import DependenciesTestSupport
internal import Foundation
internal import Models
internal import SQLiteData
internal import Testing

// `@testable` for the `DebugSnapshot` types the exhaustive assertions are written against:
// the macro makes each one as visible as the state it mirrors, but their memberwise
// initialisers are synthesised and so internal to the target that declares them.
@testable internal import ListsFeature

/// The Lists index and, through it, `ListDetail` (#19, #20).
///
/// One in-memory database per test case, built by the real `migrator` — a hand-written test
/// schema would forfeit the reason these tests can say anything about cascades (ADR-0019).
/// Worlds are seeded inline: these tests need small specific worlds that do not share a
/// seed.
///
/// Seeded rows carry **negative** ids. `inMemory()` registers a counting generator that
/// mints `…0001` upwards and never resets across a run, so a negative seed cannot collide
/// with an id the feature causes the database to mint.
///
/// Three things about `@FetchAll` under a `TestStore`, which ADR-0011 recorded as unknown
/// and these tests answered:
///
/// - It has **already run** by the time the store exists, so a seeded world is initial state
///   rather than a change to expect.
/// - A write the feature makes reaches it through a database observation, so the value is
///   read back with ``reloadIndex(_:)`` rather than by racing that observation.
/// - **It does not itself drive an assertion.** The `@ValueObservable` macro leaves the
///   property alone, so the store never records the refresh as a change of its own — it is
///   compared when some *other* change causes a snapshot, and invisible otherwise. So a
///   write that also moves tracked state is asserted with `store.expect`, and one that moves
///   nothing else — a swipe to delete — is asserted by reading `store.summaries` directly.
///   `store.expect` there would fail with "changes expected, but none occurred" against
///   state that is in fact correct.
@MainActor
@Suite(
	.dependency(\.date, .constant(.seed)),
	.dependency(\.defaultDatabase, try inMemory()),
)
internal struct ListsFeatureTests {
	@Test
	internal func creatingAListPutsItInTheIndex() async throws {
		let store = TestStore(initialState: ListsFeature.State()) { ListsFeature() }
		#expect(store.summaries.isEmpty)

		store.send(.newListButtonTapped) {
			$0.destination = .editor(
				ListEditor.State.DebugSnapshot(draft: Models.List.Draft(createdAt: .seed, name: ""))
			)
		}
		store.modify {
			$0.destination.modify(\.editor) {
				$0.draft.emoji = "🥪"
				$0.draft.name = "Lunch"
			}
		}
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// The id is the one thing not written out here: no insert site in the app names an
		// id, so it comes back from the database that minted it (ADR-0011). Everything else
		// is spelled out, or the assertion would only be agreeing with itself.
		let id = try #require(try await lists().first?.id)
		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			$0.summaries = [
				ListSummary(
					dealtCount: 0,
					itemCount: 0,
					list: Models.List(id: id, createdAt: .seed, emoji: "🥪", name: "Lunch"),
				)
			]
		}
	}

	@Test
	internal func creatingAListTrimsItsNameAndAcceptsADuplicate() async throws {
		try await seed { db in
			try db.seed {
				Models.List(id: UUID(-1), createdAt: .earlier, name: "Lunch")
			}
		}
		let store = TestStore(initialState: ListsFeature.State()) { ListsFeature() }
		#expect(store.summaries == [.seeded(id: UUID(-1), createdAt: .earlier, name: "Lunch")])

		store.send(.newListButtonTapped) {
			$0.destination = .editor(
				ListEditor.State.DebugSnapshot(draft: Models.List.Draft(createdAt: .seed, name: ""))
			)
		}
		store.modify {
			$0.destination.modify(\.editor) { $0.draft.name = "  Lunch  " }
		}
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		let created = try #require(try await lists().last)
		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			// Trimmed on the way in, and accepted alongside the name it duplicates: two Lists
			// may share a name. Repetition is the user's own weighting mechanism, and a
			// `UNIQUE` constraint could not survive two devices editing offline anyway.
			$0.summaries = [
				.seeded(id: UUID(-1), createdAt: .earlier, name: "Lunch"),
				.seeded(id: created.id, name: "Lunch"),
			]
		}
	}

	@Test
	internal func renamingAListKeepsItsIdentityAndItsItems() async throws {
		try await seed { db in
			try db.seed {
				Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
			}
		}
		let store = TestStore(initialState: ListsFeature.State()) { ListsFeature() }
		let summary = ListSummary.seeded(id: UUID(-1), itemCount: 1, name: "Lunch")
		#expect(store.summaries == [summary])

		store.send(.editSwiped(summary)) {
			$0.destination = .editor(
				ListEditor.State.DebugSnapshot(draft: Models.List.Draft(summary.list))
			)
		}
		store.modify {
			$0.destination.modify(\.editor) {
				$0.draft.drawMode = .deck
				$0.draft.name = "Lunch spots"
			}
		}
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			$0.summaries = [
				ListSummary(
					dealtCount: 0,
					itemCount: 1,
					list: Models.List(
						id: UUID(-1),
						createdAt: .seed,
						drawMode: .deck,
						name: "Lunch spots",
					),
				)
			]
		}
		// The rename is an update rather than a replacement: the Item is still attached to
		// the same row, which a delete-and-reinsert would have cascaded away.
		#expect(try await items().map(\.title) == ["Pizza"])
	}

	@Test
	internal func deletingAnEmptyListDoesNotAskFirst() async throws {
		try await seed { db in
			try db.seed {
				Models.List(id: UUID(-1), createdAt: .seed, name: "Weekend walks")
			}
		}
		let store = TestStore(initialState: ListsFeature.State()) { ListsFeature() }
		let summary = ListSummary.seeded(id: UUID(-1), name: "Weekend walks")
		#expect(store.summaries == [summary])

		// It goes with no confirmation at all — there is nothing in it to lose, and a
		// confirmation on every delete is what teaches people to tap through them.
		await store.send(.deleteSwiped(summary))?.value

		#expect(try await lists().isEmpty)
		try await reloadIndex(store)
		#expect(store.summaries.isEmpty)
	}

	@Test
	internal func deletingAListWithItemsConfirmsFirstAndCascades() async throws {
		try await seed { db in
			try db.seed {
				Models.List(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Films")
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Heat")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Aliens")
				ListDraw(itemID: UUID(-1), createdAt: .seed)

				Models.List(id: UUID(-2), createdAt: .later, name: "Lunch")
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-2), title: "Pizza")
			}
		}
		let store = TestStore(initialState: ListsFeature.State()) { ListsFeature() }
		let films = ListSummary(
			dealtCount: 1,
			itemCount: 2,
			list: Models.List(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Films"),
		)
		#expect(
			store.summaries == [
				films,
				.seeded(id: UUID(-2), createdAt: .later, itemCount: 1, name: "Lunch"),
			]
		)

		store.send(.deleteSwiped(films)) {
			$0.destination = .confirmDeletion(
				ListsFeature.ConfirmDeletion.State.DebugSnapshot(
					itemCount: 2,
					listID: UUID(-1),
					name: "Films",
				)
			)
		}
		// Nothing has gone yet: raising the confirmation is the whole of what the swipe did.
		#expect(try await lists().count == 2)

		// `Prompt` nils the destination out on the way through, so the dialog's dismissal is
		// the feature's own behaviour rather than SwiftUI's, replayed.
		await store.send(.destination(.confirmDeletion(.deleteButtonTapped))) {
			$0.destination = nil
		}?.value

		#expect(try await lists().map(\.name) == ["Lunch"])
		// Deleting a List deletes its Items, and their draw rows with them. The other List's
		// Item is untouched.
		#expect(try await items().map(\.title) == ["Pizza"])
		#expect(try await draws().isEmpty)

		try await reloadIndex(store)
		#expect(
			store.summaries == [.seeded(id: UUID(-2), createdAt: .later, itemCount: 1, name: "Lunch")]
		)
	}

	@Test
	internal func listsSortByCreatedAtThenID() async throws {
		// Seeded out of order in both keys. `Second` and `Third` share an instant, so only the
		// id tie-break can separate them — and it must separate them the same way on every
		// device, which is the whole reason the sort is `(createdAt, id)` and not `createdAt`.
		try await seed { db in
			try db.seed {
				Models.List(id: UUID(-2), createdAt: .later, name: "Third")
				Models.List(id: UUID(-3), createdAt: .seed, name: "First")
				Models.List(id: UUID(-1), createdAt: .later, name: "Second")
			}
		}
		let store = TestStore(initialState: ListsFeature.State()) { ListsFeature() }

		#expect(
			store.summaries == [
				.seeded(id: UUID(-3), name: "First"),
				.seeded(id: UUID(-1), createdAt: .later, name: "Second"),
				.seeded(id: UUID(-2), createdAt: .later, name: "Third"),
			]
		)
	}
}

// MARK: - Reading and seeding

extension ListsFeatureTests {
	/// The in-memory database the suite trait handed this test case.
	private var database: any DatabaseWriter {
		Dependency(\.defaultDatabase).wrappedValue
	}

	/// Runs the index query again and hands the result to the store's `@FetchAll`.
	///
	/// A write the feature makes reaches that property through a database observation, which
	/// arrives on its own schedule. Waiting on the write's task is not enough, so this makes
	/// the refresh the test asserts against a thing the test asked for.
	private func reloadIndex(_ store: TestStore<ListsFeature>) async throws {
		try await store.state.$summaries.load()
	}

	private func seed(_ write: @escaping @Sendable (Database) throws -> Void) async throws {
		try await database.write(write)
	}

	private func draws() async throws -> [ListDraw] {
		try await database.read { db in try ListDraw.all.fetchAll(db) }
	}

	private func items() async throws -> [Item] {
		try await database.read { db in try Item.all.order { ($0.createdAt, $0.id) }.fetchAll(db) }
	}

	private func lists() async throws -> [Models.List] {
		try await database.read { db in
			try Models.List.all.order { ($0.createdAt, $0.id) }.fetchAll(db)
		}
	}
}

extension ListSummary {
	/// A plain, undealt summary of a seeded List — the shape most of these worlds are made
	/// of, so that only what a test is actually about has to be written out.
	fileprivate static func seeded(
		id: Models.List.ID,
		createdAt: Date = .seed,
		itemCount: Int = 0,
		name: String,
	) -> Self {
		ListSummary(
			dealtCount: 0,
			itemCount: itemCount,
			list: Models.List(id: id, createdAt: createdAt, name: name),
		)
	}
}

extension Date {
	/// The instant `@Dependency(\.date)` reports throughout this target.
	internal static let seed = Date(timeIntervalSince1970: 1_234_567_890)

	/// A minute before ``seed``, and a minute after it. Ordering is asserted by seeding
	/// `createdAt` explicitly rather than by letting the clock run — and where a test seeds a
	/// row alongside one the feature creates, the two must differ here rather than fall
	/// through to a tie-break on how two UUIDs happen to collate.
	internal static let earlier = seed.addingTimeInterval(-60)
	internal static let later = seed.addingTimeInterval(60)
}
