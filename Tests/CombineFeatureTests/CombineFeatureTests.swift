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
// initialisers are synthesised and so internal to the target that declares them. The two
// screens `ComboDetail` presents are declared in targets of their own, so their snapshots —
// and `RandomiseFeature`'s pool, which is internal — are reached the same way.
@testable internal import CombineFeature
@testable internal import ListDetailFeature
@testable internal import RandomiseFeature

/// The Combine index and the one form (#23), and `ComboDetail` — a Combo's member Lists and
/// its pooled draw (#24).
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

		// Nothing ticked yet, so the footer prompts rather than counting a pool of zero.
		let editor = try #require(store.destination?.editor)
		#expect(editor.poolFooter == .prompt)

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
		#expect(store.destination?.editor?.poolFooter == .pool(count: 3))

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
		#expect(store.destination?.editor?.poolFooter == .pool(count: 1))

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
		#expect(store.destination?.editor?.poolFooter == .pool(count: 2))
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
		#expect(state.poolFooter == .pool(count: 1))

		// The other iPhone deletes the List this form has ticked.
		try await database.write { db in
			try Models.List.find(UUID(-1)).delete().execute(db)
		}
		try await state.$options.load()
		#expect(state.options.isEmpty)

		// The tick survives in the delta — the user did ask for it, and the form does not
		// quietly edit their input — but nothing on the checklist can show it.
		#expect(state.selectedListIDs == [UUID(-1)])
		#expect(state.selectedOptions.isEmpty)

		// So the footer says "Pick the Lists to draw from." rather than "0 items in the pool."
		// over a checklist with nothing ticked on it.
		//
		// Asserted as the value the view renders, not as the ingredients it would have branched
		// on: deriving this in `State` is what makes the decision testable at all, and this
		// assertion fails if it is ever taken back off `selectedOptions`.
		#expect(state.poolFooter == .prompt)
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
		#expect(store.destination?.editor?.poolFooter == .pool(count: 2))

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

// MARK: - The Combo's detail

extension CombineFeatureTests {
	@Test
	internal func theDetailShowsItsMemberListsWithCountsOnly() async throws {
		try await seed { db in
			try db.seed {
				// A Deck, part-way through, so that a member row showing `Deck · 1 of 2 left`
				// would be visible here. It reads `2 items`: counts only, in Combine, everywhere
				// — a Combo pools every Item of every member regardless of what that List has
				// dealt (ADR-0007).
				Models.List.deckLunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Sushi")
				ListDraw(itemID: UUID(-1), createdAt: .seed)

				Models.List.films
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-2), title: "Heat")

				// Not a member, and its Item is older than every other — so it would sort first,
				// and be counted, if the members query were not scoped to the Combo.
				Models.List(id: UUID(-3), createdAt: .earlier, name: "Chores")
				Item(id: UUID(-4), createdAt: .earlier, listID: UUID(-3), title: "Washing up")

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .seed, listID: UUID(-2))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = try #require(store.summaries.first)

		// Pushed as optional child state, the same idiom the sheets use and the same one the
		// Lists tab pushes its detail with — a `.navigationDestination(item:)` rather than a
		// stack of paths (ADR-0013).
		//
		// `combo` and `members` are spelled out rather than left to the snapshot's default.
		// That default is a lazy `_snapshotType`, which traps the moment the comparison reads
		// it — so a fetched property in an expected state is supplied or it takes the test
		// process down.
		store.send(.rowTapped(summary)) {
			$0.detail = ComboDetail.State.DebugSnapshot(
				combo: summary.combo,
				destination: nil,
				detail: nil,
				draws: [],
				members: [
					ListOption(itemCount: 2, list: .deckLunch),
					ListOption(itemCount: 1, list: .films),
				],
			)
		}

		let detail = try #require(store.detail)
		#expect(detail.itemCount == 3)
		#expect(detail.randomiseCaption == .pool(count: 3))
		#expect(detail.canRandomise)
	}

	@Test
	internal func theDisabledCaptionsSayWhichOfTheTwoThingsIsMissing() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
			}
		}

		// The screen's state on its own, with no store around it: what is under test is the
		// property the pinned bar's caption is chosen by, and driving a live query to refresh
		// underneath a `TestStore` would be testing the observation rather than the choice.
		var state = ComboDetail.State(combo: Combo(id: UUID(-1), createdAt: .seed, name: "Friday night"))

		// Nothing in the Combo at all: the thing to add is a List, and it is added here.
		#expect(state.randomiseCaption == .noLists)
		#expect(state.canRandomise == false)

		try await database.write { db in
			try db.seed {
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}
		try await state.$members.load()

		// A member List, and nothing in it. A different sentence because it asks for something
		// different — Items, added on a screen this one is two taps from. One prompt covering
		// both would name neither.
		#expect(state.members.map(\.list.name) == ["Lunch"])
		#expect(state.randomiseCaption == .noItems)
		#expect(state.canRandomise == false)

		try await database.write { db in
			try db.seed {
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
			}
		}
		try await state.$members.load()

		// And the one state in which the button is live, captioned with the pool rather than
		// with a reason. `canRandomise` is read off the caption, so the two can never disagree
		// — a caption explaining a dimmed button beside a button that is not is the failure
		// this rules out.
		#expect(state.randomiseCaption == .pool(count: 1))
		#expect(state.canRandomise)
	}

	@Test
	internal func thePoolIsEveryItemOfEveryMemberListFlattened() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				// The same title twice in one member List, and a third copy in another. None of
				// them is deduplicated: repetition is the user's own weighting mechanism, and it
				// works across member Lists exactly as it does within one (ADR-0004).
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Models.List.films
				Item(id: UUID(-3), createdAt: .later, listID: UUID(-2), title: "Pizza")

				// Not a member. Its Item sorts first, so an unscoped pool would deal it.
				Models.List(id: UUID(-3), createdAt: .earlier, name: "Chores")
				Item(id: UUID(-4), createdAt: .earlier, listID: UUID(-3), title: "Washing up")

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .seed, listID: UUID(-2))
				// The row two devices adding Lunch offline leave behind. Membership is
				// deduplicated by `listID` when the pool is built, so Lunch contributes its two
				// Items once rather than four times and its weight is not silently doubled
				// (ADR-0008).
				ComboList(id: UUID(-3), comboID: UUID(-1), createdAt: .later, listID: UUID(-1))
			}
		}
		let combo = Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")

		// The sheet's state on its own, unmounted, so nothing has drawn: what is under test is
		// the pool, which is where this ticket's half of the draw lives. That every pick is
		// uniform over whatever pool it is handed — and so that a 100-item List dominates a
		// 3-item one in a Combo they share — is `RandomiseFeatureTests`' claim about
		// `State.draw()`, made once for both surfaces (ADR-0016).
		let state = RandomiseFeature.State(scope: .combo(combo))
		#expect(state.pool.map(\.id) == [UUID(-1), UUID(-2), UUID(-3)])
		#expect(state.pool.map(\.title) == ["Pizza", "Pizza", "Pizza"])
		#expect(state.result == nil)

		// Three entries and three chances, from two member Lists — and each one knows which
		// List it came from, which is the only thing telling the three apart on the sheet.
		#expect(state.sourceLists.map(\.name) == ["Lunch", "Films"])
	}

	// The generator note `ListDetailTests` gives: `withRandomNumberGenerator` has no test
	// value, so a test that draws has to say which generator it draws from. The system one
	// deliberately — the pool below holds a single Item, so the pick is fixed whatever the
	// sequence, and seeding a generator here would suggest the result depended on it.
	@Test(.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(SystemRandomNumberGenerator())))
	internal func theDetailIsWhatPresentsTheRandomiseSheetAndItNamesTheSourceList() async throws {
		let lunch = Models.List.lunch
		let pizza = Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
		try await seed { db in
			try db.seed {
				lunch
				pizza
				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = try #require(store.summaries.first)

		store.send(.rowTapped(summary)) {
			$0.detail = ComboDetail.State.DebugSnapshot(
				combo: summary.combo,
				destination: nil,
				detail: nil,
				draws: [],
				members: [ListOption(itemCount: 1, list: .lunch)],
			)
		}

		// You open a Combo, then randomise it — there is no Randomise on an index row, exactly
		// as on the Lists tab (ADR-0016). The sheet is handed a `DrawScope.combo` and nothing
		// else, and it has drawn its opening result by the time this returns.
		store.send(.detail(.randomiseButtonTapped)) {
			$0.detail?.destination = .randomise(
				RandomiseFeature.State.DebugSnapshot(
					drawToken: 1,
					pool: [pizza],
					result: .item(pizza),
					scope: .combo(summary.combo),
					// The member Lists, so the sheet can name the one the result came from. Two
					// identical titles from different Lists are otherwise indistinguishable, and
					// no draw is persisted to look one up afterwards.
					sourceLists: [lunch],
				)
			)
		}
		#expect(store.detail?.destination?.randomise?.sourceList == lunch)
	}

	@Test(.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(SystemRandomNumberGenerator())))
	internal func aComboDrawIgnoresItsMembersDeckStateAndWritesNoneOfItsOwn() async throws {
		// Lunch is a Deck with its one Item already dealt. Opened on its own it is exhausted;
		// pooled into a Combo it contributes that Item anyway — a Combo's draw is governed only
		// by its own `drawMode` and its own rows (ADR-0007). The pool holding it is therefore
		// also what makes the pick below forced.
		let deck = Models.List.deckLunch
		let pizza = Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
		try await seed { db in
			try db.seed {
				deck
				pizza
				ListDraw(itemID: UUID(-1), createdAt: .seed)

				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = try #require(store.summaries.first)

		store.send(.rowTapped(summary)) {
			$0.detail = ComboDetail.State.DebugSnapshot(
				combo: summary.combo,
				destination: nil,
				detail: nil,
				draws: [],
				members: [ListOption(itemCount: 1, list: deck)],
			)
		}
		store.send(.detail(.randomiseButtonTapped)) {
			$0.detail?.destination = .randomise(
				RandomiseFeature.State.DebugSnapshot(
					drawToken: 1,
					pool: [pizza],
					result: .item(pizza),
					scope: .combo(summary.combo),
					sourceLists: [deck],
				)
			)
		}

		// The write a deal would make is queued on the same serialised writer, so this empty
		// write is a wait rather than a sleep — and there is nothing to wait for, which is the
		// point.
		try await database.write { _ in }

		// Not one row moved. Drawing from a Combo writes no `ListDraw` row, so Lunch's own deck
		// is exactly where it was; and it writes no `ComboDraw` row either, because the Combo is
		// plain — a plain Combo pools everything on every tap and keeps no memory of it.
		#expect(try await listDraws().map(\.itemID) == [UUID(-1)])
		#expect(try await draws().isEmpty)
	}

	// The same generator note as above, for the member List's own draw at the foot of this
	// test: a one-item pool makes the pick fixed whatever the sequence.
	@Test(.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(SystemRandomNumberGenerator())))
	internal func aMemberRowPushesTheRealListDetail() async throws {
		let lunch = Models.List.lunch
		let pizza = Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
		try await seed { db in
			try db.seed {
				lunch
				pizza
				Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = try #require(store.summaries.first)
		let member = ListOption(itemCount: 1, list: lunch)

		store.send(.rowTapped(summary)) {
			$0.detail = ComboDetail.State.DebugSnapshot(
				combo: summary.combo,
				destination: nil,
				detail: nil,
				draws: [],
				members: [member],
			)
		}

		// The *real* `ListDetail`, three levels of optional child state deep — the same screen
		// the Lists tab pushes, holding the same List record, with nothing conditional on which
		// tab presented it (ADR-0014). Its own `draws` and `items` are its own queries, which is
		// what makes it that screen rather than a copy of it.
		store.send(.detail(.memberTapped(member))) {
			$0.detail?.detail = ListDetail.State.DebugSnapshot(
				destination: nil,
				draws: [],
				items: [pizza],
				list: lunch,
			)
		}

		// And it keeps its own pinned Randomise, drawing from that List alone: the scope below
		// is `.list`, so the row this deals writes to `ListDraw` and the Combo's deck never
		// hears about it. There is no flag suppressing the button because a Combo presented it.
		store.send(.detail(.detail(.randomiseButtonTapped))) {
			$0.detail?.detail?.destination = .randomise(
				RandomiseFeature.State.DebugSnapshot(
					drawToken: 1,
					pool: [pizza],
					result: .item(pizza),
					scope: .list(lunch),
					// Empty on the Lists path however it was reached: a List's result has one
					// possible source and the sheet says nothing about provenance.
					sourceLists: [],
				)
			)
		}
	}
}

// MARK: - The Combo's own Deck

/// A Combo Deck deals each pooled Item at most once, against `ComboDraw` rows of its own
/// (#25).
///
/// The same mechanism as a List's Deck in a second table, so what is worth asserting here is
/// what *differs*: the subquery is scoped to the Combo, because an Item belongs to any number
/// of them; and the two surfaces' decks are independent in both directions (ADR-0007). That
/// each draw is uniform over whatever pool it is handed, and that exhaustion lands on the draw
/// after the last card rather than on it, are `RandomiseFeatureTests`' claims about
/// `State.draw()`, made once for both surfaces (ADR-0016) — and restated below as arithmetic
/// over a *pooled* deck, which is the shape this ticket adds.
///
/// The generator note the rest of this suite gives holds throughout: `withRandomNumberGenerator`
/// has no test value, so a test that draws has to say which generator it draws from. The system
/// one, deliberately — either the pick is forced by a one-card pool, or the claim is relational
/// and the result is read from the store rather than written down.
extension CombineFeatureTests {
	@Test
	internal func aComboDeckDrawsOnlyOverPooledItemsItHasNotDealt() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Sushi")

				Models.List.films
				Item(id: UUID(-3), createdAt: .later, listID: UUID(-2), title: "Heat")

				// Friday night pools both Lists and has dealt Pizza.
				Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .seed, listID: UUID(-2))
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))

				// Weeknights pools Lunch alone and has dealt Sushi — the same table, a different
				// Combo, and an Item both of them hold.
				Combo(id: UUID(-2), createdAt: .later, drawMode: .deck, name: "Weeknights")
				ComboList(id: UUID(-3), comboID: UUID(-2), createdAt: .seed, listID: UUID(-1))
				ComboDraw(id: UUID(-2), comboID: UUID(-2), createdAt: .seed, itemID: UUID(-2))
			}
		}
		let friday = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		let weeknights = Combo(id: UUID(-2), createdAt: .later, drawMode: .deck, name: "Weeknights")

		// **The subquery is scoped, and this is what that buys.** Friday night has dealt Pizza
		// and has Sushi and Heat left; Weeknights has dealt Sushi and has Pizza left. An
		// unscoped `NOT IN comboDraws` — the shape `Item.undealt(in:)` can afford, because an
		// Item belongs to exactly one List — would leave Friday night only Heat and Weeknights
		// nothing at all, each Combo emptying the other's deck.
		#expect(
			RandomiseFeature.State(scope: .combo(friday)).pool.map(\.title) == ["Sushi", "Heat"]
		)
		#expect(
			RandomiseFeature.State(scope: .combo(weeknights)).pool.map(\.title) == ["Pizza"]
		)

		// The very same rows, read by the very same Combo turned plain. Switching a Deck back to
		// plain preserves its rows and pools everything regardless — which is what lets switching
		// back resume where it left off rather than start again, exactly as a List's does.
		let plain = Combo(id: UUID(-1), createdAt: .seed, name: "Friday night")
		#expect(
			RandomiseFeature.State(scope: .combo(plain)).pool.map(\.title)
				== ["Pizza", "Sushi", "Heat"]
		)
	}

	@Test(.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(SystemRandomNumberGenerator())))
	internal func dealingFromAComboDeckWritesItsOwnRowAndTakesTheItemOutOfThePool() async throws {
		let combo = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		let sushi = Item(id: UUID(-2), createdAt: .later, listID: UUID(-1), title: "Sushi")
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				sushi

				combo
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				// One card already gone, so the pick below is forced and may be written down.
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))
			}
		}

		let store = TestStore(initialState: RandomiseFeature.State(scope: .combo(combo))) {
			RandomiseFeature()
		} changes: {
			$0.dealt = [sushi.id: 1]
			$0.drawToken = 1
			$0.result = .item(sushi)
		}

		// The pool shrinks by one on every draw, because the row the draw wrote takes the Item it
		// dealt back out of the query the pool is (ADR-0021). It travels in this closure because
		// the deal announces itself: `dealSettled` is sent once the write has landed *and* the
		// pool has been reloaded, so the two changes belong to one action.
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = [:]
			$0.pool = []
		}

		// The row names both ids, unlike a `ListDraw`: an Item belongs to any number of Combos,
		// so its own id would not say which of them dealt it. And the id is not written out —
		// no insert site in the app names one (ADR-0011).
		let rows = try await draws()
		let dealt = try #require(rows.first { $0.itemID == UUID(-2) })
		#expect(rows.count == 2)
		#expect(dealt.comboID == UUID(-1))
		#expect(dealt.createdAt == .seed)
		// And not one `ListDraw` row, which is the rule rather than the gap: drawing from a
		// Combo leaves every member List's own deck exactly as it was (ADR-0007).
		#expect(try await listDraws().isEmpty)
	}

	@Test(.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(SystemRandomNumberGenerator())))
	internal func dealingRightThroughAComboDeckProducesEveryPooledCardExactlyOnce() async throws {
		// Four cards across two member Lists, two of them sharing a title: a Deck deals Items
		// rather than titles, so "Pizza" in two Lists is two cards and comes out twice. That is
		// what makes this a claim about a multiset rather than a set — the same reason repetition
		// is the user's own weighting mechanism (ADR-0004).
		let combo = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Sushi")

				Models.List.films
				Item(id: UUID(-3), createdAt: .later, listID: UUID(-2), title: "Pizza")
				Item(id: UUID(-4), createdAt: .later, listID: UUID(-2), title: "Heat")

				combo
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .seed, listID: UUID(-2))

				// Seeded spent, so that the one draw a test cannot state — the opening one, which
				// happens synchronously at mount — is the one draw whose outcome is not a pick.
				for offset in 0...3 {
					ComboDraw(
						id: UUID(-1 - offset),
						comboID: UUID(-1),
						createdAt: .seed,
						itemID: UUID(-1 - offset),
					)
				}
			}
		}
		let pool = try await pooledItems()
		#expect(pool.count == 4)

		let store = TestStore(initialState: RandomiseFeature.State(scope: .combo(combo))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .exhausted
		}

		// The exhausted sheet names the Combo, not a member List: "Every item in *Friday night*
		// has been dealt once." is the same screen and the same announcement a List Deck shows,
		// reading its name off the scope (ADR-0016).
		#expect(store.state.scope.name == "Friday night")
		#expect(store.canDrawAgain)

		// **Reshuffle deletes that Combo's rows** and deals the first card of the run.
		await store.send(.reshuffleButtonTapped)?.value
		await store.receive(\.deckReshuffled, timeout: .seconds(1)) {
			$0.drawToken = 2
			// Emptied by the reshuffle, then holding the one card it dealt straight afterwards.
			$0.dealt = store.dealt
			$0.result = store.result
			$0.pool = pool
		}
		var dealt = [try #require(store.result?.item)]
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = [:]
			$0.pool = pool.filter { !dealt.contains($0) }
		}

		// Then right through to the last card. Which card each draw lands on is the generator's
		// business, and so is whether the row that removes it has landed by the time the store is
		// asked — both are read from it rather than written down. The claims are the two
		// underneath: no card comes out twice, and the pool is always the deck minus what has
		// been dealt.
		for draw in 2...pool.count {
			store.send(.againButtonTapped) {
				$0.drawToken = draw + 1
				$0.dealt = store.dealt
				$0.result = store.result
				$0.pool = store.pool
			}
			let card = try #require(store.result?.item)
			#expect(!dealt.contains(card))
			dealt.append(card)

			// Each deal settles before the next tap, which is what keeps `dealt` down to the
			// in-flight window rather than accumulating the whole run.
			await store.receive(\.dealSettled, timeout: .seconds(1)) {
				$0.dealt = [:]
				$0.pool = pool.filter { !dealt.contains($0) }
			}
		}

		// The multiset of what came out *is* the pool, titles and all.
		#expect(dealt.count == pool.count)
		#expect(Set(dealt) == Set(pool))
		#expect(dealt.map(\.title).sorted() == ["Heat", "Pizza", "Pizza", "Sushi"])
		#expect(try await Set(draws().map(\.itemID)) == Set(pool.map(\.id)))
		// One row per card and no more. `comboDraws` is keyed on a surrogate id, so a card dealt
		// twice would land a second row here rather than trip a constraint — which is what made
		// the stale-pool window silent on this surface until the sheet started filtering against
		// everything it had dealt.
		#expect(try await draws().count == pool.count)
		// And the sheet is holding nothing of its own: every deal has settled, so the table is
		// the whole record.
		#expect(store.dealt.isEmpty)

		// And exhaustion lands on the draw after the last card — N + 1, never N.
		store.send(.againButtonTapped) {
			$0.drawToken = pool.count + 2
			$0.result = .exhausted
			$0.pool = []
		}
	}

	@Test(.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(SystemRandomNumberGenerator())))
	internal func theTwoSurfacesDecksAreIndependentInBothDirections() async throws {
		// Lunch is a Deck with its one Item already dealt: opened on its own it is exhausted.
		let deck = Models.List.deckLunch
		let pizza = Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
		let combo = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		try await seed { db in
			try db.seed {
				deck
				pizza
				ListDraw(itemID: UUID(-1), createdAt: .seed)

				combo
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}

		// **An exhausted member List does not shrink the Combo's pool.** Pizza is in it, because
		// a Combo pools every Item of every member regardless of what that List has dealt — so
		// this Combo Deck has a card to deal, and the pick is forced.
		let store = TestStore(initialState: RandomiseFeature.State(scope: .combo(combo))) {
			RandomiseFeature()
		} changes: {
			$0.dealt = [pizza.id: 1]
			$0.drawToken = 1
			$0.result = .item(pizza)
		}
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = [:]
			$0.pool = []
		}

		// One direction: the Combo's deal wrote its own row and left Lunch's exactly as it was.
		#expect(try await draws().map(\.itemID) == [UUID(-1)])
		#expect(try await listDraws().map(\.itemID) == [UUID(-1)])

		// The other: Lunch's own Reshuffle, from the real `ListDetail` — the screen a member row
		// pushes — puts Lunch's card back and leaves the Combo's deck spent. "Dealt in Lunch" and
		// "dealt in Friday night" are separate facts, and this is the direction most likely to be
		// "fixed" by someone who has not read ADR-0007.
		let listStore = TestStore(initialState: ListDetail.State(list: deck)) { ListDetail() }
		#expect(listStore.isExhausted)
		await listStore.send(.reshuffleButtonTapped)?.value

		#expect(try await listDraws().isEmpty)
		#expect(try await draws().map(\.itemID) == [UUID(-1)])

		// And the Combo is still exhausted with Lunch's deck full: its pool is the Item, and its
		// own row is the only thing that takes it out.
		#expect(RandomiseFeature.State(scope: .combo(combo)).pool.isEmpty)
	}

	@Test
	internal func theDetailCountsItsOwnDeckDownAndIgnoresADrawOfAnUnpooledItem() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Sushi")
				Item(id: UUID(-3), createdAt: .seed, listID: UUID(-1), title: "Ramen")

				// Not a member, and its Item is dealt by this Combo — the row a List unticked on
				// *another* device leaves behind, which ADR-0023's cleanup cannot reach. It must
				// count for nothing, or the caption reads `1 of 3 left` over a deck that has
				// dealt one card.
				Models.List.films
				Item(id: UUID(-4), createdAt: .seed, listID: UUID(-2), title: "Heat")

				Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))
				ComboDraw(id: UUID(-2), comboID: UUID(-1), createdAt: .later, itemID: UUID(-4))
			}
		}

		// The screen's state on its own, with no store around it: what is under test is the
		// arithmetic the pinned bar's caption is made of, and driving a live query to refresh
		// underneath a `TestStore` would be testing the observation rather than the arithmetic.
		let state = ComboDetail.State(
			combo: Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		)

		// `Deck · 2 of 3 left`, and the button live. The stale draw counts for nothing — the
		// same condition `ComboSummary.index` joins on, so the row and the screen it opens
		// cannot come to disagree.
		#expect(state.draws.map(\.itemID) == [UUID(-1)])
		#expect(state.dealtCount == 1)
		#expect(state.remainingCount == 2)
		#expect(state.randomiseCaption == .deck(remaining: 2, total: 3))
		#expect(state.canRandomise)
		#expect(state.isExhausted == false)
	}

	@Test
	internal func reshuffleFromASpentComboDeckPutsBackItsOwnRowsAndNoOthers() async throws {
		let combo = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		try await seed { db in
			try db.seed {
				// A member List that is a Deck part-way through its own run, so this Reshuffle has
				// something it could wrongly put back.
				Models.List.deckLunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-1), title: "Sushi")
				ListDraw(itemID: UUID(-1), createdAt: .seed)

				// And a second Combo over the same List, mid-run: "dealt in Friday night" and
				// "dealt in Weeknights" are separate facts too.
				Combo(id: UUID(-2), createdAt: .later, drawMode: .deck, name: "Weeknights")
				ComboList(id: UUID(-2), comboID: UUID(-2), createdAt: .seed, listID: UUID(-1))
				ComboDraw(id: UUID(-3), comboID: UUID(-2), createdAt: .seed, itemID: UUID(-1))

				combo
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))
				ComboDraw(id: UUID(-2), comboID: UUID(-1), createdAt: .later, itemID: UUID(-2))
			}
		}
		let store = TestStore(initialState: ComboDetail.State(combo: combo)) { ComboDetail() }

		// Spent, and the button reads **Reshuffle** rather than going dim: `canRandomise` stays
		// true here, and a dimmed Reshuffle would take away the only way out of a spent Combo
		// Deck.
		#expect(store.randomiseCaption == .deck(remaining: 0, total: 2))
		#expect(store.isExhausted)
		#expect(store.canRandomise)

		await store.send(.reshuffleButtonTapped)?.value

		// This Combo's rows and not one more. Read rather than `expect`ed, for the reason
		// ``deletingAnEmptyComboDoesNotAskFirst`` gives: Reshuffle moves nothing but a
		// `@FetchAll`.
		#expect(try await draws().map(\.comboID) == [UUID(-2)])
		#expect(try await listDraws().map(\.itemID) == [UUID(-1)])

		try await reloadDraws(store)
		#expect(store.draws.isEmpty)
		#expect(store.randomiseCaption == .deck(remaining: 2, total: 2))
		#expect(store.isExhausted == false)
	}

	@Test
	internal func addingAnItemOrAMemberListUnExhaustsAComboDeck() async throws {
		let combo = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")
				Models.List.films

				combo
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))
			}
		}
		var state = ComboDetail.State(combo: combo)
		#expect(state.isExhausted)

		// A new Item arrives undealt, because a draw row is keyed on the Item's identity and
		// nothing else touches it — the same rule that un-exhausts a List Deck, one surface over.
		try await seed { db in
			try db.seed {
				Item(id: UUID(-2), createdAt: .later, listID: UUID(-1), title: "Sushi")
			}
		}
		try await state.$members.load()
		#expect(state.randomiseCaption == .deck(remaining: 1, total: 2))
		#expect(state.isExhausted == false)

		// And so does a whole member List, which is the case a List Deck has no equivalent of:
		// the pool grew by a List's worth of Items this Combo has never dealt.
		try await seed { db in
			try db.seed {
				Item(id: UUID(-3), createdAt: .later, listID: UUID(-2), title: "Heat")
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .later, listID: UUID(-2))
			}
		}
		try await state.$members.load()
		#expect(state.randomiseCaption == .deck(remaining: 2, total: 3))
		#expect(state.isExhausted == false)
	}

	@Test
	internal func untickingAListTakesThisCombosDrawsOfItsItemsAndNoOthers() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Item(id: UUID(-1), createdAt: .seed, listID: UUID(-1), title: "Pizza")

				Models.List.films
				Item(id: UUID(-2), createdAt: .seed, listID: UUID(-2), title: "Heat")

				// Friday night pools both and has dealt both.
				Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
				ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .seed, listID: UUID(-2))
				ComboDraw(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, itemID: UUID(-1))
				ComboDraw(id: UUID(-2), comboID: UUID(-1), createdAt: .later, itemID: UUID(-2))

				// Weeknights pools Films too, and has dealt the very same Item.
				Combo(id: UUID(-2), createdAt: .later, drawMode: .deck, name: "Weeknights")
				ComboList(id: UUID(-3), comboID: UUID(-2), createdAt: .seed, listID: UUID(-2))
				ComboDraw(id: UUID(-3), comboID: UUID(-2), createdAt: .seed, itemID: UUID(-2))

				// And Films is a Deck in its own right, part-way through its own run.
				ListDraw(itemID: UUID(-2), createdAt: .seed)
			}
		}
		let store = TestStore(initialState: CombineFeature.State()) { CombineFeature() }
		let summary = try #require(store.summaries.first)

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
						ComboList(id: UUID(-2), comboID: UUID(-1), createdAt: .seed, listID: UUID(-2)),
					],
				)
			)
		}

		let options = try #require(store.destination?.editor?.options)
		store.send(.destination(.editor(.listToggled(options[1])))) {
			$0.destination.modify(\.editor) { $0.unticked = [UUID(-2)] }
		}
		await store.send(.destination(.editor(.saveButtonTapped)))?.value

		// Friday night's memory of Heat goes with the membership: those cards are not in its
		// deck any more, so neither is the record of dealing them (ADR-0023). Its draw of Pizza
		// stays, because Lunch is still a member.
		let rows = try await draws()
		#expect(rows.filter { $0.comboID == UUID(-1) }.map(\.itemID) == [UUID(-1)])

		// **And not one row more.** Weeknights still holds Heat and keeps its own draw of it —
		// the delete is scoped by Combo as well as by Item, or unticking here would empty every
		// other Combo's memory of the same Items. Films' own `ListDraw` row is untouched too:
		// the form reaches no `ListDraw` row at all (ADR-0007).
		#expect(rows.filter { $0.comboID == UUID(-2) }.map(\.itemID) == [UUID(-2)])
		#expect(try await listDraws().map(\.itemID) == [UUID(-2)])

		let friday = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		let weeknights = Combo(id: UUID(-2), createdAt: .later, drawMode: .deck, name: "Weeknights")
		try await reloadIndex(store)
		store.expect {
			$0.destination = nil
			// `Deck · 0 of 1 left` for Friday night: it is down to Lunch, and its one card is
			// dealt. The deleted rows leave no trace in the arithmetic — the point of deleting
			// them rather than filtering them out forever.
			$0.summaries = [
				ComboSummary(combo: friday, dealtCount: 1, itemCount: 1, listCount: 1),
				ComboSummary(combo: weeknights, dealtCount: 1, itemCount: 1, listCount: 1),
			]
		}

		// So re-adding Films gives this Combo a clean card rather than one that arrives dealt,
		// which is the failure leaving the row behind would have produced — a deck that shrank
		// for a reason nothing on screen ever showed. Not a gesture this test drives through the
		// form: what is under test is the row, and the form's insert is `anUntouchedMembership…`'s
		// claim.
		try await database.write { db in
			try db.seed {
				ComboList(id: UUID(-4), comboID: UUID(-1), createdAt: .later, listID: UUID(-2))
			}
		}
		// Read rather than `expect`ed: nothing was sent, so there is no action whose changes
		// this could be — the third note on the suite says why that makes `expect` the wrong
		// tool here.
		//
		// `Deck · 1 of 2 left`, not `0 of 2`: Heat is back in the pool and back in the deck.
		try await reloadIndex(store)
		#expect(
			store.summaries == [
				ComboSummary(combo: friday, dealtCount: 1, itemCount: 2, listCount: 2),
				ComboSummary(combo: weeknights, dealtCount: 1, itemCount: 1, listCount: 1),
			]
		)
		#expect(RandomiseFeature.State(scope: .combo(friday)).pool.map(\.title) == ["Heat"])
	}

	@Test
	internal func aComboWithNothingToDealIsPromptingRatherThanExhausted() async throws {
		try await seed { db in
			try db.seed {
				Models.List.lunch
				Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
				ComboList(id: UUID(-1), comboID: UUID(-1), createdAt: .seed, listID: UUID(-1))
			}
		}
		let combo = Combo(id: UUID(-1), createdAt: .seed, drawMode: .deck, name: "Friday night")
		let state = ComboDetail.State(combo: combo)

		// A Combo Deck pooling nothing has dealt everything it holds and is *not* exhausted: its
		// Randomise is disabled with a prompt to add Items, rather than offering to put back
		// cards that were never dealt. Both prompts come before the Deck caption for that reason.
		#expect(state.randomiseCaption == .noItems)
		#expect(state.canRandomise == false)
		#expect(state.isExhausted == false)
	}
}

// MARK: - Reading and seeding

extension CombineFeatureTests {
	/// The in-memory database the suite trait handed this test case.
	private var database: any DatabaseWriter {
		Dependency(\.defaultDatabase).wrappedValue
	}

	/// Reloads a Combo detail's own draw rows. See ``reloadIndex(_:)`` for why a test has to
	/// ask.
	private func reloadDraws(_ store: TestStore<ComboDetail>) async throws {
		try await store.state.$draws.load()
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

	/// Every `ComboDraw` row in the database, whichever Combo authored it — the table a member
	/// List's own draw must leave exactly as it found it (ADR-0007).
	private func draws() async throws -> [ComboDraw] {
		try await database.read { db in
			try ComboDraw.all.order { ($0.createdAt, $0.itemID) }.fetchAll(db)
		}
	}

	/// Every member List's *own* draw rows, whichever List's Item they belong to — the table a
	/// Combo's draw must leave exactly as it found it (ADR-0007).
	private func listDraws() async throws -> [ListDraw] {
		try await database.read { db in try ListDraw.all.order(by: \.itemID).fetchAll(db) }
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

	/// The one Combo these worlds build, pooled and in the sheet's own order — so a test can
	/// say "the multiset that came out is the pool" without restating what the pool is.
	///
	/// Read back rather than written down. Items seeded in the same instant are separated by
	/// the id tie-break, and whether `UUID(-1)` collates before `UUID(-2)` is SQLite's business
	/// rather than something a test should assert by assuming it.
	private func pooledItems() async throws -> [Item] {
		try await database.read { db in
			try Item.inCombo(UUID(-1)).order { ($0.createdAt, $0.id) }.fetchAll(db)
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
	/// ``lunch`` as a Deck, for the worlds asking what a Combo does with a member's own deck
	/// state. The answer is nothing, on both sides: a Combo pools its Items regardless, and
	/// drawing from the Combo leaves its rows alone.
	fileprivate static let deckLunch = Models.List(
		id: UUID(-1),
		createdAt: .seed,
		drawMode: .deck,
		name: "Lunch",
	)

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
