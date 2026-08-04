//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
// Public because `Models.List.ID` aliases `Foundation.UUID`, and `State.selectedListIDs` is
// public.
public import Foundation
public import Models

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// The one form a Combo is built in: name, emoji, draw mode **and** its membership, over a
/// `Combo.Draft` and a set of ticked List ids.
///
/// One feature covers both create and edit, exactly as ``ListEditor`` does — a draft is the
/// difference, and `upsert` does the right thing without the form having to know which it
/// is. What is different here is that membership travels with it: a separate picker sheet
/// would give membership two homes for a screen whose only content is that membership
/// (ADR-0020).
///
/// **Nothing exists until Save.** Every write in this app is immediate and global, so a form
/// that created the Combo on `+` would put a record named "New Combo" on your other iPhones
/// before it meant anything.
@Feature
public struct ComboEditor {
	public struct State {
		public var draft: Combo.Draft

		/// What this Combo holds right now — live, not a snapshot taken when the form opened.
		///
		/// Built in `init` rather than declared on the property the way the index's reads are,
		/// for the reason `ListDetail`'s is: the query is scoped to one Combo, and the id only
		/// exists once there is a draft to read it from. A new Combo has no id yet, so it
		/// matches on the empty `IN ()` SQLite permits — nothing, which is exactly right.
		@FetchAll internal var memberships: [ComboList]

		/// Every List, with its Item count — the checklist, live, so a List made on another
		/// device while the form is open appears in it.
		@FetchAll(ListOption.all) internal var options: [ListOption]

		/// The Lists this sitting ticked, and the ones it unticked.
		///
		/// **The form records the changes the user made, not the set they left behind.** A
		/// snapshot would make Save rewrite the whole membership from state that went stale the
		/// moment another device touched it: open the form with Lunch ticked, let another
		/// iPhone add Films, rename the Combo, and saving would delete Films — a membership
		/// this sitting never saw and the user never touched. That is precisely the silent loss
		/// ADR-0008 chose a join table to avoid, reintroduced one layer up.
		///
		/// Holding the deltas instead means Save deletes only what was unticked here and
		/// inserts only what was ticked here, so an edit from another device merges rather than
		/// losing a race with an unrelated rename.
		internal var ticked: Set<Models.List.ID> = []
		internal var unticked: Set<Models.List.ID> = []

		/// What the checklist shows ticked: what the Combo holds, plus this sitting's ticks,
		/// minus its unticks.
		///
		/// A `Set`, so the form can never show a List twice — the duplicate rows ADR-0008
		/// accepts come from two devices, not from here, and a Combo that has them ticks its
		/// List once.
		public var selectedListIDs: Set<Models.List.ID> {
			Set(memberships.map(\.listID)).union(ticked).subtracting(unticked)
		}

		/// Trimmed and non-empty is the rule for a name; this is where it is enforced, and
		/// the only thing gating Save. Neither the emoji nor the membership gates it: zero
		/// member Lists is legal, and there is no "combining needs two Lists" rule — it would
		/// block building a Combo up one List at a time.
		public var isSavable: Bool { !draft.name.trimmedForStorage.isEmpty }

		/// What the `Lists` footer counts: the Items the Combo would pool as it currently
		/// stands.
		///
		/// Deduplicated by construction — ``selectedOptions`` comes off a `Set` and each
		/// ``ListOption`` appears once — so this agrees with the count `ComboSummary` will
		/// select back out of the database once the form is saved.
		public var poolCount: Int {
			selectedOptions.reduce(0) { $0 + $1.itemCount }
		}

		/// The ticked Lists that are still *on* the checklist — what the footer counts, and
		/// what it branches on.
		///
		/// Derived through ``options`` rather than read off ``selectedListIDs`` because a List
		/// deleted while the form is open leaves an id behind that nothing can show. Branching
		/// the footer on the ids would then read "0 items in the pool." over a checklist with
		/// nothing ticked on it, where "Pick the Lists to draw from." is what that is.
		internal var selectedOptions: [ListOption] {
			options.filter { selectedListIDs.contains($0.id) }
		}

		public init(draft: Combo.Draft) {
			self.draft = draft
			let comboIDs = draft.id.map { [$0] } ?? []
			_memberships = FetchAll(ComboList.where { $0.comboID.in(comboIDs) })
		}
	}

	public enum Action {
		case cancelButtonTapped
		case listToggled(ListOption)
		case saveButtonTapped
	}

	/// The in-flight save, so a second tap can be told there is one.
	@StoreTaskID var save

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .cancelButtonTapped:
				store.addTask { try store.dismiss() }

			case .listToggled(let option):
				// Each tick lands in one set and is cleared from the other, so toggling back and
				// forth leaves no residue and a List is never both ticked and unticked.
				if state.selectedListIDs.contains(option.id) {
					state.ticked.remove(option.id)
					state.unticked.insert(option.id)
				} else {
					state.unticked.remove(option.id)
					state.ticked.insert(option.id)
				}

			case .saveButtonTapped:
				// The same rule the Save button is gated on, asked of the state rather than
				// recomputed here, so the two cannot come to disagree.
				//
				// And not a second time while the first write is still in flight. The draft's
				// id is still `nil` until the sheet dismisses, so a second `upsert` inserts a
				// second row rather than updating the first — and two Combos with one name is
				// legal here, so it would land silently.
				guard state.isSavable, !save.isRunning else { return }
				var edited = state.draft
				edited.name = edited.name.trimmedForStorage
				let draft = edited
				// Ticks are filtered through `options` so a List deleted while the form was open
				// cannot be inserted against a foreign key that has gone. Unticks are not: the
				// row is being deleted by `listID`, and a List that no longer exists has already
				// taken its membership with it.
				let added = state.options.map(\.id).filter(state.ticked.contains)
				let removed = Array(state.unticked)

				@Dependency(\.date.now) var now
				@Dependency(\.defaultDatabase) var database
				store.addTask(id: save) {
					// `withErrorReporting` reports the failure and returns `nil`. The sheet
					// stays up when it does: dismissing would throw the draft away and leave
					// the user believing it saved, which is the one outcome worse than the
					// write failing.
					// `Void?` is spelled out because the closure returns nothing, and an
					// inferred `()?` is a warning.
					let saved: Void? = await withErrorReporting {
						// One transaction, so a Combo can never be left holding the membership
						// of the edit before it — or, on a create, no membership at all.
						try await database.write { db in
							try writeCombo(draft, adding: added, removing: removed, at: now, to: db)
						}
					}
					guard saved != nil else { return }
					try store.dismiss()
				}
			}
		}
	}
}

/// Upserts the Combo and applies the membership changes this sitting made.
///
/// **Only what the user ticked and unticked.** A membership neither touched is left exactly
/// as it is — same row, same id, same `createdAt` — so an edit arriving from another device
/// survives a save here, and so a save does not resurface an untouched membership everywhere
/// else as a deletion followed by a fresh insert.
///
/// **Duplicate rows for a ticked List are left where they are.** Two devices adding the same
/// List offline is a legal steady state under ADR-0008, and deduplication belongs where that
/// ADR puts it — in the pool, when it is built. Collapsing them here would mean a save
/// issuing a hard, global delete of a row another device authored.
///
/// A free function rather than a method on ``ComboEditor``, so the database write captures
/// the values it needs and not the feature.
private func writeCombo(
	_ draft: Combo.Draft,
	adding: [Models.List.ID],
	removing: [Models.List.ID],
	at now: Date,
	to db: Database,
) throws {
	// `RETURNING` because a created Combo's id is minted by the schema's `newID()` default —
	// no insert site in the app names an id (ADR-0011) — and the membership rows about to be
	// written need it.
	// The statement is bound before the `guard` because a trailing closure inside a `guard`
	// condition reads as the statement's own body.
	let upsert = Combo.upsert { draft }.returning(\.id)
	guard let comboID = try upsert.fetchOne(db) else { throw ComboNotSaved() }

	if !removing.isEmpty {
		try ComboList
			.inCombo(comboID)
			.and(ComboList.where { $0.listID.in(removing) })
			.delete()
			.execute(db)
	}

	// A List ticked here that another device had already added needs no second row: the tick
	// asked for membership, which it has.
	let existingListIDs = try Set(ComboList.inCombo(comboID).select { $0.listID }.fetchAll(db))
	let inserts = adding
		.filter { !existingListIDs.contains($0) }
		.map { ComboList.Draft(comboID: comboID, createdAt: now, listID: $0) }
	guard !inserts.isEmpty else { return }
	// One statement for the lot, rather than a prepare and a step per newly-ticked List.
	try ComboList.insert { inserts }.execute(db)
}

/// An upsert that wrote no row, which SQLite does not do — but `RETURNING` is typed as
/// optional, and the alternative to naming this is a force unwrap on the one statement the
/// whole save hangs off.
private struct ComboNotSaved: Error {}
