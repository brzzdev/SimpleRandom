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

		/// Every List, with its Item count — the checklist, live, so a List made on another
		/// device while the form is open appears in it.
		@FetchAll(ListOption.all) internal var options: [ListOption]

		/// The ticked Lists. A `Set`, so the form itself can never hold a List twice — the
		/// duplicate rows ADR-0008 accepts come from two devices, not from here.
		public var selectedListIDs: Set<Models.List.ID>

		/// Trimmed and non-empty is the rule for a name; this is where it is enforced, and
		/// the only thing gating Save. Neither the emoji nor the membership gates it: zero
		/// member Lists is legal, and there is no "combining needs two Lists" rule — it would
		/// block building a Combo up one List at a time.
		public var isSavable: Bool { !draft.name.trimmedForStorage.isEmpty }

		/// What the `Lists` footer counts: the Items the Combo would pool as it currently
		/// stands.
		///
		/// Deduplicated by construction — ``selectedListIDs`` is a `Set` and each ``ListOption``
		/// appears once — so this agrees with the count `ComboSummary` will select back out of
		/// the database once the form is saved.
		public var poolCount: Int {
			options.reduce(0) { total, option in
				selectedListIDs.contains(option.id) ? total + option.itemCount : total
			}
		}

		/// The ticked Lists in the app's one sort order, and the whole of what Save writes.
		///
		/// Ordered through ``options`` rather than by sorting the ids, so membership rows are
		/// created in the order the checklist shows them. It also drops any id whose List has
		/// gone since the form opened, which would otherwise fail the foreign key.
		internal var selectedListIDsInOrder: [Models.List.ID] {
			options.lazy.map(\.id).filter(selectedListIDs.contains)
		}

		public init(draft: Combo.Draft, selectedListIDs: Set<Models.List.ID> = []) {
			self.draft = draft
			self.selectedListIDs = selectedListIDs
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
				// A tick is a toggle, and the `Set` is what makes it idempotent in both
				// directions.
				if state.selectedListIDs.contains(option.id) {
					state.selectedListIDs.remove(option.id)
				} else {
					state.selectedListIDs.insert(option.id)
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
				let listIDs = state.selectedListIDsInOrder

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
							try writeCombo(draft, memberListIDs: listIDs, at: now, to: db)
						}
					}
					guard saved != nil else { return }
					try store.dismiss()
				}
			}
		}
	}
}

/// Upserts the Combo and reconciles its memberships to the ticked Lists.
///
/// The reconciliation keeps the oldest row for each still-ticked List and deletes the rest,
/// rather than deleting every row and reinserting: a membership nobody touched keeps its id
/// and its `createdAt`, so it does not resurface on every other device as a deletion
/// followed by a fresh insert.
///
/// Keeping the *oldest* is what also collapses the duplicate rows ADR-0008 accepts — two
/// devices adding the same List offline. Leaving them would be harmless, since the pool
/// deduplicates by `listID` when it is built; tidying them here means the next save is the
/// last place the duplicate exists rather than the first of many.
///
/// A free function rather than a method on ``ComboEditor``, so the database write captures
/// the four values it needs and not the feature.
private func writeCombo(
	_ draft: Combo.Draft,
	memberListIDs: [Models.List.ID],
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

	// `(createdAt, id)` ascending, so "the oldest row" means the same row on every device.
	let existing = try ComboList.inCombo(comboID).order { ($0.createdAt, $0.id) }.fetchAll(db)
	var keptListIDs: Set<Models.List.ID> = []
	var doomedIDs: [ComboList.ID] = []
	for row in existing {
		let isFirstOfATickedList =
			memberListIDs.contains(row.listID) && keptListIDs.insert(row.listID).inserted
		if !isFirstOfATickedList { doomedIDs.append(row.id) }
	}

	try ComboList.where { $0.id.in(doomedIDs) }.delete().execute(db)
	for listID in memberListIDs where !keptListIDs.contains(listID) {
		try ComboList
			.insert { ComboList.Draft(comboID: comboID, createdAt: now, listID: listID) }
			.execute(db)
	}
}

/// An upsert that wrote no row, which SQLite does not do — but `RETURNING` is typed as
/// optional, and the alternative to naming this is a force unwrap on the one statement the
/// whole save hangs off.
private struct ComboNotSaved: Error {}
