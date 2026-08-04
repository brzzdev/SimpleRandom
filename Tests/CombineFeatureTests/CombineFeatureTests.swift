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
@testable internal import CombineFeature

/// The Combine index and the one form (#23). `ComboDetail` is #24.
///
/// One in-memory database per test case, built by the real `migrator` — a hand-written test
/// schema would forfeit the reason these tests can say anything about cascades (ADR-0019).
/// Worlds are seeded inline: these tests need small specific worlds that do not share a
/// seed.
///
/// Seeded rows carry **negative** ids, as `ListsFeatureTests` does. `inMemory()` registers a
/// counting generator that mints `…0001` upwards and never resets across a run, so a
/// negative seed cannot collide with an id the feature causes the database to mint.
///
/// `@FetchAll` and `@FetchOne` behave here exactly as `ListsFeatureTests` documents: they
/// have already run by the time the store exists, a write reaches them through a database
/// observation rather than through the write's own task, and they drive no assertion of
/// their own — so a write that moves nothing else is asserted by reading the property back
/// after ``reloadIndex(_:)`` rather than with `store.expect`.
@MainActor
@Suite(
	.dependency(\.date, .constant(.seed)),
	.dependency(\.defaultDatabase, try inMemory()),
)
internal struct CombineFeatureTests {
	// MARK: - Creating

	@Test
	internal func creatingAComboSavesItAndItsMembership() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Sushi")

				Models.List.films
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-2), title: "Heat")
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		#expect(store.summaries.isEmpty)
		#expect(store.listCount == 2)

		// `options` is spelled out rather than left to the snapshot's default. That default is
		// a lazy `_snapshotType`, which traps the moment the comparison reads it — so a
		// `@FetchAll` in an expected state is supplied or it takes the test process down. Here
		// it doubles as the assertion that the checklist is every List, newest last, each with
		// its own Item count.
		store.send(.newComboButtonTapped) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(createdAt: .seed, name: ""),
					options: [
						ListOption(itemCount: 2, list: .lunch),
						ListOption(itemCount: 1, list: .films),
					],
					ticked: [],
				)
			)
		}

		// Nothing ticked yet, so the footer reads "Pick the Lists to draw from." rather than a
		// pool of zero.
		let editor = try #require(store.destination?.editor)
		#expect(editor.poolCount == 0)

		store.modify {
			$0.destination.modify(\.editor) {
				$0.draft.emoji = "🍿"
				$0.draft.name = "Friday night"
			}
		}
		store.send(.destination(.editor(.listToggled(editor.options[0])))) {
			$0.destination.modify(\.editor) { $0.ticked = [UUID(-1)] }
		}
		store.send(.destination(.editor(.listToggled(editor.options[1])))) {
			$0.destination.modify(\.editor) { $0.ticked = [UUID(-1), UUID(-2)] }
		}
		// The live footer, and the whole point of the one form: three Items across two Lists,
		// counted before anything has been written.
		#expect(store.destination?.editor?.poolCount == 3)

		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// The id is the one thing not written out here: no insert site in the app names an id,
		// so it comes back from the database that minted it (ADR-0011).
		let comboID = try #require(try await combos().first?.id)
		// Membership is rows in the join table, written in the order the checklist showed them
		// — not an array column on the Combo (ADR-0008). Their ids are minted by the database
		// for the same reason the Combo's is, so they are read back rather than written out.
		let rows = try await memberships()
		#expect(rows.map(\.listID) == [UUID(-1), UUID(-2)])
		#expect(rows.allSatisfy { $0.comboID == comboID })

		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			$0.summaries = [
				ComboSummary(
					combo: Combo(id: comboID, createdAt: .seed, emoji: "🍿", name: "Friday night"),
					dealtCount: 0,
					itemCount: 3,
					listCount: 2,
				)
			]
		}
	}

	@Test
	internal func aComboWithNoMemberListsIsLegal() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }

		store.send(.newComboButtonTapped) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(createdAt: .seed, name: ""),
					options: [ListOption(itemCount: 0, list: .lunch)],
					ticked: [],
				)
			)
		}
		store.modify {
			$0.destination.modify(\.editor) { $0.draft.name = "  Friday night  " }
		}

		// Membership gates nothing: zero member Lists is legal, and there is no "combining
		// needs two Lists" rule — it would block building a Combo up one List at a time.
		#expect(store.destination?.editor?.isSavable == true)
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		let comboID = try #require(try await combos().first?.id)
		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			// Trimmed on the way in, like a List's name.
			$0.summaries = [.seeded(id: comboID, name: "Friday night")]
		}
		#expect(try await memberships().isEmpty)
	}

	@Test
	internal func aWhitespaceOnlyNameSavesNothing() async throws {
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }

		store.send(.newComboButtonTapped) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(createdAt: .seed, name: ""),
					options: [],
					ticked: [],
				)
			)
		}
		store.modify {
			$0.destination.modify(\.editor) { $0.draft.name = "   " }
		}

		// A name is trimmed and non-empty, so there is nothing here to save. The Save button
		// is disabled on the same rule, and this is the reducer refusing anyway — the button
		// is a courtesy, not the enforcement.
		#expect(store.destination?.editor?.isSavable == false)
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// The sheet stays up, holding what was typed, rather than dismissing on a save that
		// did not happen.
		#expect(try await combos().isEmpty)
		#expect(store.destination?.editor != nil)
	}

	// MARK: - Editing membership

	@Test
	internal func editingAComboReopensTheFormWithItsMembersTicked() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Models.List.films
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-2), title: "Heat")
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-2), title: "Aliens")

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = ComboSummary.seeded(id: UUID(-1), itemCount: 1, listCount: 1)
		#expect(store.summaries == [summary])

		// The form reopens with what the Combo already holds, which is what makes it *the*
		// home for membership rather than one of two (ADR-0020).
		store.send(.editSwiped(summary)) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(summary.combo),
					options: [
						ListOption(itemCount: 1, list: .lunch),
						ListOption(itemCount: 2, list: .films),
					],
					ticked: [.lunchOf(UUID(-1), createdAt: .seed)],
				)
			)
		}
		#expect(store.destination?.editor?.poolCount == 1)

		// Swap Lunch out for Films, and make it a Deck while we are here.
		let options = try #require(store.destination?.editor?.options)
		store.modify {
			$0.destination.modify(\.editor) { $0.draft.drawMode = .deck }
		}
		store.send(.destination(.editor(.listToggled(options[0])))) {
			$0.destination.modify(\.editor) { $0.unticked = [UUID(-1)] }
		}
		store.send(.destination(.editor(.listToggled(options[1])))) {
			$0.destination.modify(\.editor) { $0.ticked = [UUID(-2)] }
		}
		#expect(store.destination?.editor?.selectedListIDs == [UUID(-2)])
		#expect(store.destination?.editor?.poolCount == 2)
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// The membership was replaced rather than the Combo, and the Lists themselves are
		// untouched: a Combo points at them and does not own them.
		let rows = try await memberships()
		#expect(rows.map(\.listID) == [UUID(-2)])
		#expect(try await lists().map(\.name) == ["Lunch", "Films"])

		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			$0.summaries = [
				ComboSummary(
					combo: Combo(
						id: UUID(-1),
						createdAt: .seed,
						drawMode: .deck,
						name: "Friday night",
					),
					dealtCount: 0,
					itemCount: 2,
					listCount: 1,
				)
			]
		}
	}

	@Test
	internal func anUntouchedMembershipKeepsItsIdentity() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Models.List.films

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .earlier, listID: UUID(-1))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = ComboSummary.seeded(id: UUID(-1), listCount: 1)

		store.send(.editSwiped(summary)) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(summary.combo),
					options: [
						ListOption(itemCount: 0, list: .lunch),
						ListOption(itemCount: 0, list: .films),
					],
					ticked: [.lunchOf(UUID(-1), createdAt: .earlier)],
				)
			)
		}
		let films = try #require(store.destination?.editor?.options.last)
		store.send(.destination(.editor(.listToggled(films)))) {
			$0.destination.modify(\.editor) { $0.ticked = [UUID(-2)] }
		}
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// Adding a List leaves the existing membership exactly where it was — same id, same
		// `createdAt`. A delete-all-and-reinsert would have resurfaced it on every other
		// device as a deletion followed by a fresh row.
		let rows = try await memberships()
		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			$0.summaries = [.seeded(id: UUID(-1), listCount: 2)]
		}
		#expect(rows.count == 2)
		#expect(
			rows[0]
				== ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .earlier, listID: UUID(-1))
		)
		#expect(rows[1].listID == UUID(-2))
		#expect(rows[1].createdAt == .seed)
	}

	// MARK: - Membership changed on another device while the form is open

	@Test
	internal func aMembershipAddedElsewhereSurvivesAnUnrelatedSave() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Models.List.films
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-2), title: "Heat")

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = ComboSummary.seeded(id: UUID(-1), itemCount: 1, listCount: 1)

		store.send(.editSwiped(summary)) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(summary.combo),
					options: [
						ListOption(itemCount: 1, list: .lunch),
						ListOption(itemCount: 1, list: .films),
					],
					ticked: [.lunchOf(UUID(-1), createdAt: .seed)],
				)
			)
		}

		// Another iPhone adds Films while the form sits open. Not a gesture this screen owns.
		try await database.write { db in
			try db.seed {
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .later, listID: UUID(-2))
			}
		}

		// The user renames the Combo and nothing else — neither delta set mentions a List.
		store.modify {
			$0.destination.modify(\.editor) { $0.draft.name = "Movie night" }
		}
		#expect(store.destination?.editor?.ticked.isEmpty == true)
		#expect(store.destination?.editor?.unticked.isEmpty == true)
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// Films survives. Under a selection snapshot taken when the form opened, saving the
		// rename would have deleted it — a membership this sitting never saw. Asserted against
		// the database rather than the index, because it is the write that was wrong.
		#expect(try await memberships().map(\.listID) == [UUID(-1), UUID(-2)])
		#expect(try await combos().map(\.name) == ["Movie night"])

		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			$0.summaries = [.seeded(id: UUID(-1), itemCount: 2, listCount: 2, name: "Movie night")]
		}
	}

	@Test
	internal func aMembershipRemovedElsewhereIsNotRecreated() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Models.List.films
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-2), title: "Heat")

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .later, listID: UUID(-2))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = ComboSummary.seeded(id: UUID(-1), itemCount: 2, listCount: 2)

		store.send(.editSwiped(summary)) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(summary.combo),
					options: [
						ListOption(itemCount: 1, list: .lunch),
						ListOption(itemCount: 1, list: .films),
					],
					ticked: [
						.lunchOf(UUID(-1), createdAt: .seed),
						ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .later, listID: UUID(-2)),
					],
				)
			)
		}

		// The other iPhone drops Films instead.
		try await database.write { db in
			try ComboList.find(UUID(-2)).delete().execute(db)
		}

		store.modify {
			$0.destination.modify(\.editor) { $0.draft.name = "Movie night" }
		}
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// Saving does not put it back. A snapshot taken when the form opened still held Films,
		// so it would have reinserted the row the other device had just deleted.
		#expect(try await memberships().map(\.listID) == [UUID(-1)])

		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			$0.summaries = [.seeded(id: UUID(-1), itemCount: 1, listCount: 1, name: "Movie night")]
		}
	}

	@Test
	internal func aTickedListDeletedElsewhereLeavesNothingTickedOnScreen() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
			}
		}

		// The form's state on its own, with no store around it: what is under test is the two
		// properties the `Lists` footer chooses between, and driving a live query to refresh
		// underneath a `TestStore` would be testing the observation rather than the choice.
		var state = ComboEditor.State(draft: Combo.Draft(createdAt: .seed, name: "Friday night"))
		#expect(state.options.map(\.list.name) == ["Lunch"])

		state.ticked = [UUID(-1)]
		#expect(state.selectedOptions.map(\.id) == [UUID(-1)])
		#expect(state.poolCount == 1)

		// The other iPhone deletes the List this form has ticked.
		try await database.write { db in
			try Models.List.find(UUID(-1)).delete().execute(db)
		}
		try await state.$options.load()
		#expect(state.options.isEmpty)

		// The tick survives in the delta — the user did ask for it, and the form does not
		// quietly edit their input — but nothing on the checklist can show it.
		#expect(state.selectedListIDs == [UUID(-1)])
		// So the footer reads "Pick the Lists to draw from." rather than "0 items in the pool."
		// over a checklist with nothing ticked on it. This is the branch the view takes.
		#expect(state.selectedOptions.isEmpty)
		#expect(state.poolCount == 0)
	}

	// MARK: - The deduplicated pool

	@Test
	internal func aDuplicatedMembershipCountsOnce() async throws {
		// The world two devices adding the same List offline produces. No `UNIQUE` is
		// available outside the primary key, so this is a legal state rather than a corrupt
		// one — and left uncounted-for it would silently double Lunch's weight (ADR-0008).
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Sushi")

				Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .later, listID: UUID(-1))
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }

		// `1 List · Deck · 1 of 2 left`, not `2 Lists · Deck · 2 of 4 left`.
		#expect(
			store.summaries == [
				ComboSummary(
					combo: Combo(
						id: UUID(-1),
						createdAt: .seed,
						drawMode: .deck,
						name: "Friday night",
					),
					dealtCount: 1,
					itemCount: 2,
					listCount: 1,
				)
			]
		)

		// And the form ticks it once, because a `Set` is what it holds the selection in.
		let summary = try #require(store.summaries.first)
		store.send(.editSwiped(summary)) {
			$0.destination = .editor(
				.editing(
					Combo.Draft(summary.combo),
					// Both rows arrive; the `Set` the form derives from them ticks Lunch once.
					options: [ListOption(itemCount: 2, list: .lunch)],
					ticked: [
						.lunchOf(UUID(-1), createdAt: .seed),
						.lunchOf(UUID(-2), createdAt: .later),
					],
				)
			)
		}
		#expect(store.destination?.editor?.poolCount == 2)

		// Saving leaves both rows exactly where they are. Deduplication belongs in the pool,
		// which is where ADR-0008 puts it — a save that collapsed them would be issuing a hard,
		// global delete of a row another device authored, which nobody asked this form to do.
		await store.send(.destination(.editor(.saveButtonTapped)))?.value
		try await reloadIndex(store)
		store.expect { $0.destination = nil }
		#expect(
			try await memberships() == [
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1)),
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .later, listID: UUID(-1)),
			]
		)
		// And the caption still reads `1 List`, which is the whole point of the deduplication
		// being a property of the query rather than of the rows.
		#expect(store.summaries.map(\.listCount) == [1])
	}

	@Test
	internal func aDrawOfAnItemNoLongerInThePoolLeavesTheArithmeticAlone() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Models.List.films
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-2), title: "Heat")

				Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				// Dealt back when Films was a member, and Films is not one now.
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-2))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }

		// `1 List · Deck · 1 of 1 left` — a stale draw counts for nothing rather than reading
		// the Deck down below zero.
		let summary = try #require(store.summaries.first)
		#expect(summary.dealtCount == 0)
		#expect(summary.itemCount == 1)
		#expect(summary.remainingCount == 1)
	}

	// MARK: - Deleting

	@Test
	internal func deletingAnEmptyComboDoesNotAskFirst() async throws {
		try await seed { db in
			try db.seed {
				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = ComboSummary.seeded(id: UUID(-1))
		#expect(store.summaries == [summary])

		// It goes with no confirmation at all — there is no arrangement in it to lose.
		await store.send(.deleteSwiped(summary))?.value

		#expect(try await combos().isEmpty)
		try await reloadIndex(store)
		#expect(store.summaries.isEmpty)
	}

	@Test
	internal func deletingAComboWithMembersConfirmsFirstAndKeepsTheLists() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))

				Combo(id: UUID(-2), createdAt: .later, name: "Weeknights")
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = ComboSummary(
			combo: Combo(id: UUID(-1), createdAt: .seed, name: "Friday night"),
			dealtCount: 1,
			itemCount: 1,
			listCount: 1,
		)
		#expect(
			store.summaries == [
				summary,
				.seeded(id: UUID(-2), createdAt: .later, name: "Weeknights"),
			]
		)

		store.send(.deleteSwiped(summary)) {
			$0.destination = .confirmDeletion(
				CombineFeature.ConfirmDeletion.State.DebugSnapshot(
					comboID: UUID(-1),
					name: "Friday night",
				)
			)
		}
		// Nothing has gone yet: raising the confirmation is the whole of what the swipe did.
		#expect(try await combos().count == 2)

		// `Prompt` nils the destination out on the way through, so the alert's dismissal is
		// the feature's own behaviour rather than SwiftUI's, replayed.
		await store.send(.destination(.confirmDeletion(.deleteButtonTapped))) {
			$0.destination = nil
		}?.value

		#expect(try await combos().map(\.name) == ["Weeknights"])
		// The memberships and the draw rows cascade away with the Combo — and the Lists in it
		// are kept, which is exactly what the alert promised.
		#expect(try await memberships().isEmpty)
		#expect(try await draws().isEmpty)
		#expect(try await lists().map(\.name) == ["Lunch"])
		#expect(try await items().map(\.title) == ["Pizza"])
	}

	@Test
	internal func deletingAListShrinksTheCombosThatHeldIt() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Models.List.films
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-2), title: "Heat")

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .seed, listID: UUID(-2))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		#expect(store.summaries == [.seeded(id: UUID(-1), itemCount: 2, listCount: 2)])

		// Not a gesture this screen owns — it is the Lists tab's delete, arriving through the
		// schema. The Combo silently shrinks, and nothing warned first (ADR-0008).
		try await database.write { db in
			try Models.List.find(UUID(-1)).delete().execute(db)
		}

		try await reloadIndex(store)
		#expect(store.summaries == [.seeded(id: UUID(-1), itemCount: 1, listCount: 1)])
		#expect(store.listCount == 1)
	}

	// MARK: - Ordering

	@Test
	internal func combosSortByCreatedAtThenID() async throws {
		// Seeded out of order in both keys. `Second` and `Third` share an instant, so only the
		// id tie-break can separate them — and it must separate them the same way on every
		// device, which is the whole reason the sort is `(createdAt, id)` and not `createdAt`.
		try await seed { db in
			try db.seed {
				Combo(id: UUID(-2), createdAt: .later, name: "Third")
				Combo(id: UUID(-3), createdAt: .seed, name: "First")
				Combo(id: UUID(-1), createdAt: .later, name: "Second")
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }

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

extension CombineFeatureTests {
	/// The in-memory database the suite trait handed this test case.
	private var database: any DatabaseWriter {
		Dependency(\.defaultDatabase).wrappedValue
	}

	/// Runs the index's queries again and hands the results to the store's reads.
	///
	/// A write the feature makes reaches those properties through a database observation,
	/// which arrives on its own schedule. Waiting on the write's task is not enough, so this
	/// makes the refresh the test asserts against a thing the test asked for.
	private func reloadIndex(_ store: TestStore<CombineFeature>) async throws {
		try await store.state.$listCount.load()
		try await store.state.$summaries.load()
	}

	private func seed(_ write: @escaping @Sendable (Database) throws -> Void) async throws {
		try await database.write(write)
	}

	private func combos() async throws -> [Combo] {
		try await database.read { db in
			try Combo.all.order { ($0.createdAt, $0.id) }.fetchAll(db)
		}
	}

	private func draws() async throws -> [ComboDraw] {
		try await database.read { db in try ComboDraw.all.fetchAll(db) }
	}

	private func items() async throws -> [Item] {
		try await database.read { db in try Item.all.order { ($0.createdAt, $0.id) }.fetchAll(db) }
	}

	private func lists() async throws -> [Models.List] {
		try await database.read { db in
			try Models.List.all.order { ($0.createdAt, $0.id) }.fetchAll(db)
		}
	}

	private func memberships() async throws -> [ComboList] {
		try await database.read { db in
			try ComboList.all.order { ($0.createdAt, $0.id) }.fetchAll(db)
		}
	}
}

extension ComboSummary {
	/// A plain, undealt summary of a seeded Combo — the shape most of these worlds are made
	/// of, so that only what a test is actually about has to be written out.
	fileprivate static func seeded(
		id: Combo.ID,
		createdAt: Date = .seed,
		itemCount: Int = 0,
		listCount: Int = 0,
		name: String = "Friday night",
	) -> Self {
		ComboSummary(
			combo: Combo(id: id, createdAt: createdAt, name: name),
			dealtCount: 0,
			itemCount: itemCount,
			listCount: listCount,
		)
	}
}

extension ComboList {
	/// A seeded membership of Lunch in the one Combo these worlds build, so a test writes the
	/// row's own identity and nothing it shares with every other row.
	fileprivate static func lunchOf(_ id: ComboList.ID, createdAt: Date) -> Self {
		ComboList(id: id, comboID: UUID(-1), createdAt: createdAt, listID: UUID(-1))
	}
}

extension ComboEditor.State.DebugSnapshot {
	/// The form as it opens: a draft, the checklist the database answers with, and the Lists
	/// already ticked.
	///
	/// `options` and `memberships` are spelled out at every call site rather than defaulted.
	/// The snapshot's own default for a `@FetchAll` is a lazy `_snapshotType`, which traps the
	/// moment the comparison reads it — so a fetched property in an expected state is supplied
	/// or it takes the test process down.
	fileprivate static func editing(
		_ draft: Combo.Draft,
		options: [ListOption],
		ticked memberships: [ComboList] = [],
	) -> Self {
		ComboEditor.State.DebugSnapshot(
			draft: draft,
			memberships: memberships,
			options: options,
			ticked: [],
			unticked: [],
		)
	}
}

extension Models.List {
	/// The two Lists most of these worlds are built from, so that a checklist assertion and
	/// the seed it is about cannot drift apart.
	fileprivate static let films = Models.List(id: UUID(-2), createdAt: .later, name: "Films")
	fileprivate static let lunch = Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")
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
