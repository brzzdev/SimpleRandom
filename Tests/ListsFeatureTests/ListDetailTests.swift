//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import Database
internal import Dependencies
internal import DependenciesTestSupport
internal import Foundation
internal import IssueReporting
internal import Models
internal import SQLiteData
internal import Testing

// `@testable` for the `DebugSnapshot` types the exhaustive assertions are written against:
// the macro makes each one as visible as the state it mirrors, but their memberwise
// initialisers are synthesised and so internal to the target that declares them.
@testable internal import ListDetailFeature
@testable internal import ListsFeature
@testable internal import RandomiseFeature

/// `ListDetail` — one List's Items (#20).
///
/// It has no test target of its own: its behaviour is exercised here, from the tab that
/// pushes it, because a test target per feature target is symmetry rather than risk
/// (ADR-0019). The conventions are ``ListsFeatureTests``' — one in-memory database per case
/// built by the real `migrator`, worlds seeded inline, and seeded rows carrying **negative**
/// ids so they cannot collide with one the counting generator mints.
@MainActor
@Suite(
	.dependency(\.date, .constant(.seed)),
	.dependency(\.defaultDatabase, try inMemory()),
)
internal struct ListDetailTests {
	@Test
	internal func addingItemsKeepsThemInInsertionOrder() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in try db.seed { lunch } }
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }
		#expect(store.items.isEmpty)

		// Three, because two would not tell insertion order from any order that happens to
		// agree with it on a pair.
		for title in ["Pizza", "Ramen", "Tacos"] {
			try await add(title, to: store)
		}

		// All three share a `createdAt` — the suite freezes the clock — so what orders them
		// here is the id tie-break alone, and the counting generator mints ids in the order
		// the sheet saved them. Insertion order therefore survives three rows created in the
		// same instant, which is the case a wall clock would never produce on demand.
		try await reloadItems(store)
		#expect(store.items.map(\.title) == ["Pizza", "Ramen", "Tacos"])
	}

	@Test
	internal func addingAnItemTrimsItsTitleAndAcceptsADuplicate() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in
			try db.seed {
				lunch
				Item(id: UUID(-1), createdAt: .earlier, listID: UUID(-1), title: "Pizza")
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }

		store.send(.newItemButtonTapped) {
			$0.editor = ItemEditor.State.DebugSnapshot(draft: Item.Draft(createdAt: .seed, listID: UUID(-1), title: ""))
		}
		store.modify {
			$0.editor?.draft.title = "  Pizza  "
		}
		await store.send(.editor(.saveButtonTapped))?.value

		// The id is the one thing not written out here: no insert site in the app names an id,
		// so it comes back from the database that minted it (ADR-0011). Everything else is
		// spelled out, or the assertion would only be agreeing with itself.
		let created = try #require(try await items().last)
		try await reloadItems(store)
		store.expect {
			$0.editor = nil
			// Trimmed on the way in, and accepted alongside the title it duplicates: two Items
			// in one List may be identical. Under uniform selection that is the user's own
			// weighting mechanism — adding "Pizza" twice doubles its odds — and nothing
			// deduplicates them (ADR-0004).
			$0.items = [
				Item(id: UUID(-1), createdAt: .earlier, listID: UUID(-1), title: "Pizza"),
				Item(id: created.id, createdAt: .seed, listID: UUID(-1), title: "Pizza"),
			]
		}
	}

	@Test
	internal func aWhitespaceOnlyTitleSavesNothing() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in try db.seed { lunch } }
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }

		store.send(.newItemButtonTapped) {
			$0.editor = ItemEditor.State.DebugSnapshot(draft: Item.Draft(createdAt: .seed, listID: UUID(-1), title: ""))
		}
		store.modify {
			$0.editor?.draft.title = "   "
		}

		// A title is trimmed and non-empty, so there is nothing here to save. The Save button
		// is disabled on the same rule, and this is the reducer refusing anyway — the button is
		// a courtesy, not the enforcement.
		let editor = try #require(store.editor)
		#expect(editor.isSavable == false)
		await store.send(.editor(.saveButtonTapped))?.value

		// The sheet stays up, holding what was typed, rather than dismissing on a save that did
		// not happen.
		#expect(try await items().isEmpty)
		#expect(store.editor != nil)
	}

	@Test
	internal func aFailedSaveKeepsTheSheetUpAndTheDraftIntact() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in try db.seed { lunch } }
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }

		store.send(.newItemButtonTapped) {
			$0.editor = ItemEditor.State.DebugSnapshot(draft: Item.Draft(createdAt: .seed, listID: UUID(-1), title: ""))
		}
		store.modify {
			$0.editor?.draft.title = "Pizza"
		}

		// The bluntest write failure available through the public API, and the only part of
		// this that is contrived: what is under test is what the editor does when the write
		// throws, not the particular reason it threw.
		try await database.write { db in try #sql("DROP TABLE items").execute(db) }

		await withExpectedIssue {
			await store.send(.editor(.saveButtonTapped))?.value
		}

		// Dismissing here would throw the draft away and leave the user believing it saved,
		// which is the one outcome worse than the write failing.
		#expect(store.editor?.draft.title == "Pizza")
	}

	@Test
	internal func editingAnItemKeepsItsIdentityAndItsPlace() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in
			try db.seed {
				lunch
				Item(id: UUID(-1), createdAt: .earlier, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Ramen")
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }
		let pizza = try #require(store.items.first)

		store.send(.rowTapped(pizza)) {
			$0.editor = ItemEditor.State.DebugSnapshot(draft: Item.Draft(pizza))
		}
		store.modify {
			$0.editor?.draft.title = "Pizza Express"
		}
		await store.send(.editor(.saveButtonTapped))?.value

		try await reloadItems(store)
		store.expect {
			$0.editor = nil
			// An update rather than a replacement: the row keeps its id, and with it the
			// `createdAt` that holds its place — a delete-and-reinsert would have minted a new
			// id and sent it to the end. It would also have taken any draw row with it, which
			// is why identity is the row and not the text.
			$0.items = [
				Item(id: UUID(-1), createdAt: .earlier, listID: UUID(-1), title: "Pizza Express"),
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Ramen"),
			]
		}
	}

	@Test
	internal func deletingAnItemDoesNotAskFirst() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in
			try db.seed {
				lunch
				Item(id: UUID(-1), createdAt: .earlier, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Ramen")
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }
		let pizza = try #require(store.items.first)

		// Straight out, with nothing raised in between: an Item is one line of text the user
		// can retype, unlike a List, which takes its Items with it.
		await store.send(.deleteSwiped(pizza))?.value

		// Read rather than `expect`ed: a delete moves nothing else, and the third note on
		// ``ListsFeatureTests`` says why that makes `expect` the wrong tool.
		try await reloadItems(store)
		#expect(store.items.map(\.title) == ["Ramen"])
		#expect(store.editor == nil)
	}

	// `withRandomNumberGenerator` has no test value — it falls through to the live one and
	// reports an issue — so a test that draws has to say which generator it draws from. The
	// system one, deliberately: the pool below holds a single Item, so the pick is fixed
	// whatever the sequence, and seeding a generator here would suggest the result depended on
	// it. ``RandomiseFeatureTests`` is where the draw itself is under test.
	@Test(.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(SystemRandomNumberGenerator())))
	internal func theDetailIsWhatPresentsTheRandomiseSheet() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		let pizza = Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
		try await seed { db in
			try db.seed {
				lunch
				pizza
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }

		// You open a List, then randomise it — there is no Randomise on an index row, which is
		// why `ListsFeature` has no case for one to send (ADR-0016). The sheet is handed a scope
		// and nothing else, and it has drawn its opening result by the time this returns.
		//
		// A one-item List makes that result predictable without the generator being seeded: it
		// is the only Item there is.
		store.send(.randomiseButtonTapped) {
			$0.randomise = RandomiseFeature.State.DebugSnapshot(
				drawToken: 1,
				pool: [pizza],
				result: .item(pizza),
				scope: .list(lunch),
			)
		}
	}

	@Test
	internal func itemsSortByCreatedAtThenIDAndOnlyShowTheirOwnList() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in
			try db.seed {
				lunch
				Models.List(id: UUID(-2), createdAt: .seed, name: "Films")

				// Seeded out of order in both keys. `Second` and `Third` share an instant, so
				// only the id tie-break can separate them — and it must separate them the same
				// way on every device, which is the whole reason the sort is `(createdAt, id)`
				// and not `createdAt`.
				Item(id: UUID(-2), createdAt: .later, listID: UUID(-1), title: "Third")
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-1), title: "First")
				Item(id: UUID(-1), createdAt: .later, listID: UUID(-1), title: "Second")

				Item(id: UUID(-4), createdAt: .earlier, listID: UUID(-2), title: "Heat")
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: lunch)) { ListDetail() }

		// The other List's Item is older than all of these, so it would sort first if the
		// query were not scoped: an Item belongs to exactly one List.
		#expect(store.items.map(\.title) == ["First", "Second", "Third"])
	}

	@Test
	internal func theIndexCaptionFollowsWhatTheDetailAddsAndDeletes() async throws {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
		try await seed { db in try db.seed { lunch } }
		let store = TestStore(initialState: ListsFeature.State()) { ListsFeature() }
		let summary = try #require(store.summaries.first)
		#expect(summary.itemCount == 0)

		// Pushed as optional child state, which is the same idiom the editor sheets use — a
		// `.navigationDestination(item:)` rather than a stack of paths (ADR-0013).
		//
		// `items` is spelled out rather than left to the snapshot's default. That default is a
		// lazy `_snapshotType`, which traps the moment the comparison reads it — so a
		// `@FetchAll` in an expected state is supplied or it takes the test process down.
		store.send(.rowTapped(summary)) {
			$0.detail = ListDetail.State.DebugSnapshot(
				draws: [],
				editor: nil,
				items: [],
				list: lunch,
				randomise: nil,
			)
		}

		store.send(.detail(.newItemButtonTapped)) {
			$0.detail?.editor = ItemEditor.State.DebugSnapshot(draft: Item.Draft(createdAt: .seed, listID: UUID(-1), title: ""))
		}
		store.modify {
			$0.detail?.editor?.draft.title = "Pizza"
		}
		await store.send(.detail(.editor(.saveButtonTapped)))?.value

		// The index is a separate `@FetchAll` over a separate query, and it is the write to
		// `items` that reaches it — nothing tells it about the child's edit.
		let pizza = try #require(try await items().first)
		try await reloadIndex(store)
		try await reloadDetailItems(store)
		store.expect {
			$0.detail?.editor = nil
			$0.detail?.items = [pizza]
			$0.summaries = [ListSummary(dealtCount: 0, itemCount: 1, list: lunch)]
		}

		await store.send(.detail(.deleteSwiped(pizza)))?.value

		// Read rather than `expect`ed, for the reason ``deletingAnItemDoesNotAskFirst`` gives.
		try await reloadIndex(store)
		try await reloadDetailItems(store)
		#expect(store.summaries.map(\.itemCount) == [0])
		#expect(store.detail?.items.isEmpty == true)
	}
}

// MARK: - Deck mode

extension ListDetailTests {
	@Test
	internal func aDeckKnowsWhatItHasDealtAndWhatItHasLeft() async throws {
		let deck = Models.List(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Lunch")
		try await seed { db in
			try db.seed {
				deck
				Models.List(id: UUID(-2), createdAt: .seed, drawMode: .deck, name: "Films")
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Ramen")
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-1), title: "Tacos")
				Item(id: UUID(-4), createdAt: .seed, listID: UUID(-2), title: "Alien")

				// One of this List's, and one of another's — which the screen must not count,
				// even though a draw row names only the Item.
				ListDraw(itemID: UUID(-1), createdAt: .seed)
				ListDraw(itemID: UUID(-4), createdAt: .seed)
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: deck)) { ListDetail() }

		// What the caption and the checkmarks are made of: `Deck · 2 of 3 left`, with the dealt
		// Item rendering secondary.
		#expect(store.dealtItemIDs == [UUID(-1)])
		#expect(store.remainingCount == 2)
		#expect(store.isExhausted == false)
	}

	@Test
	internal func aDeckIsExhaustedOnlyWhenItHasItemsAndHasDealtThemAll() async throws {
		let deck = Models.List(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Lunch")
		try await seed { db in try db.seed { deck } }

		// An empty List has dealt everything it holds and is *not* exhausted: its Randomise is
		// disabled with a prompt to add something, rather than offering to put back cards that
		// were never dealt.
		let store = TestStore(initialState: ListDetail.State(list: deck)) { ListDetail() }
		#expect(store.isExhausted == false)

		try await seed { db in
			try db.seed {
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				ListDraw(itemID: UUID(-1), createdAt: .seed)
			}
		}
		// Read rather than `expect`ed: a `@FetchAll` drives no assertion of its own, and
		// nothing else here has moved for it to be compared alongside.
		try await reloadItems(store)
		try await reloadDraws(store)
		#expect(store.items.map(\.title) == ["Pizza"])
		#expect(store.draws.map(\.itemID) == [UUID(-1)])
		#expect(store.isExhausted)

		// And an Item added to a spent Deck un-exhausts it: a new Item arrives undealt, because
		// a draw row is keyed on the Item's identity and nothing else touches it.
		try await seed { db in
			try db.seed { Item(id: UUID(-2), createdAt: .later, listID: UUID(-1), title: "Ramen") }
		}
		try await reloadItems(store)
		#expect(store.items.map(\.title) == ["Pizza", "Ramen"])
		#expect(store.isExhausted == false)
		#expect(store.remainingCount == 1)
	}

	@Test
	internal func reshufflePutsEveryDealtItemBackAndLeavesOtherListsAlone() async throws {
		let deck = Models.List(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Lunch")
		try await seed { db in
			try db.seed {
				deck
				Models.List(id: UUID(-2), createdAt: .seed, drawMode: .deck, name: "Films")
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Ramen")
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-2), title: "Alien")

				ListDraw(itemID: UUID(-1), createdAt: .seed)
				ListDraw(itemID: UUID(-2), createdAt: .seed)
				ListDraw(itemID: UUID(-3), createdAt: .seed)
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: deck)) { ListDetail() }
		#expect(store.isExhausted)

		// The whole set, hard-deleted, and not one row more: "dealt in Lunch" and "dealt in
		// Films" are separate facts, and a Deck reaches its rows through its own Items.
		await store.send(.reshuffleButtonTapped)?.value

		// Read rather than `expect`ed, for the reason ``deletingAnItemDoesNotAskFirst`` gives:
		// Reshuffle moves nothing but a `@FetchAll`.
		try await reloadDraws(store)
		#expect(store.draws.isEmpty)
		#expect(store.isExhausted == false)
		#expect(store.remainingCount == 2)
		#expect(try await draws().map(\.itemID) == [UUID(-3)])
	}

	@Test
	internal func editingAnItemKeepsItsDrawRow() async throws {
		let deck = Models.List(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Lunch")
		let pizza = Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
		try await seed { db in
			try db.seed {
				deck
				pizza
				ListDraw(itemID: UUID(-1), createdAt: .seed)
			}
		}
		let store = TestStore(initialState: ListDetail.State(list: deck)) { ListDetail() }

		store.send(.rowTapped(pizza)) {
			$0.editor = ItemEditor.State.DebugSnapshot(draft: Item.Draft(pizza))
		}
		store.modify {
			$0.editor?.draft.title = "Pizza Express"
		}
		await store.send(.editor(.saveButtonTapped))?.value

		// Identity is the row, not the text: an edit is an update to the Item that already
		// exists, so the draw keyed on its id survives being renamed. A delete-and-reinsert
		// would have taken it with it, and quietly put a dealt card back in the deck.
		try await reloadItems(store)
		store.expect {
			$0.editor = nil
			$0.items = [Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza Express")]
		}
		#expect(try await draws().map(\.itemID) == [UUID(-1)])
		#expect(store.isExhausted)
	}
}

// MARK: - Reading and seeding

extension ListDetailTests {
	/// The in-memory database the suite trait handed this test case.
	private var database: any DatabaseWriter {
		Dependency(\.defaultDatabase).wrappedValue
	}

	/// Drives the editor sheet end to end, the way a user adding an Item does.
	///
	/// The rows it hands the store's exhaustive comparison are read back from the database
	/// rather than spelled out, because this only carries the sheet — what the rows are, and
	/// what order they come out in, is the claim of whichever test called it.
	private func add(_ title: String, to store: TestStore<ListDetail>) async throws {
		store.send(.newItemButtonTapped) {
			$0.editor = ItemEditor.State.DebugSnapshot(draft: Item.Draft(createdAt: .seed, listID: UUID(-1), title: ""))
		}
		store.modify {
			$0.editor?.draft.title = title
		}
		await store.send(.editor(.saveButtonTapped))?.value

		let rows = try await items()
		try await reloadItems(store)
		store.expect {
			$0.editor = nil
			$0.items = rows
		}
	}

	/// Reloads the Items of a detail reached as the index's optional child state. See
	/// ``reloadItems(_:)`` for why a test has to ask.
	private func reloadDetailItems(_ store: TestStore<ListsFeature>) async throws {
		try await store.state.detail?.$items.load()
	}

	/// Reloads the Deck's draw rows. See ``reloadItems(_:)`` for why a test has to ask.
	private func reloadDraws(_ store: TestStore<ListDetail>) async throws {
		try await store.state.$draws.load()
	}

	/// Reloads the index the detail is pushed from. See ``reloadItems(_:)`` for why a test has
	/// to ask.
	private func reloadIndex(_ store: TestStore<ListsFeature>) async throws {
		try await store.state.$summaries.load()
	}

	/// Runs the detail's query again and hands the result to the store's `@FetchAll`.
	///
	/// A write the feature makes reaches that property through a database observation, which
	/// arrives on its own schedule. Waiting on the write's task is not enough, so this makes
	/// the refresh the test asserts against a thing the test asked for.
	private func reloadItems(_ store: TestStore<ListDetail>) async throws {
		try await store.state.$items.load()
	}

	private func seed(_ write: @escaping @Sendable (Database) throws -> Void) async throws {
		try await database.write(write)
	}

	private func items() async throws -> [Item] {
		try await database.read { db in try Item.all.order { ($0.createdAt, $0.id) }.fetchAll(db) }
	}

	/// Every draw row in the database, whichever List's Item it belongs to.
	private func draws() async throws -> [ListDraw] {
		try await database.read { db in try ListDraw.all.order(by: \.itemID).fetchAll(db) }
	}
}
