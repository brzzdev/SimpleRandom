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

		/// What this Combo already holds, and the whole of what seeds ``selectedListIDs``.
		///
		/// Built in `init` rather than declared on the property the way the index's reads are,
		/// for the reason `ListDetail`'s is: the query is scoped to one Combo, and the id only
		/// exists once there is a draft to read it from. A new Combo has no id yet, so it
		/// matches on the empty `IN ()` SQLite permits — nothing, which is exactly right.
		@FetchAll internal var memberships: [ComboList]

		/// Every List, with its Item count — the checklist, live, so a List made on another
		/// device while the form is open appears in it.
		@FetchAll(ListOption.all) internal var options: [ListOption]

		/// The ticked Lists. A `Set`, so the form itself can never hold a List twice — the
		/// duplicate rows ADR-0008 accepts come from two devices, not from here, and reopening
		/// a Combo that has them ticks its List once.
		///
		/// Seeded from ``memberships`` and then owned by the user: this is a draft like the
		/// name beside it, and nothing exists until Save.
		public var selectedListIDs: Set<Models.List.ID>

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

		/// The ticked Lists in the app's one sort order — what the footer counts, and what
		/// Save writes.
		///
		/// Ordered through ``options`` rather than by sorting the ids, so membership rows are
		/// created in the order the checklist shows them. It also drops any id whose List has
		/// gone since the form opened, which would otherwise fail the foreign key.
		internal var selectedOptions: [ListOption] {
			options.filter { selectedListIDs.contains($0.id) }
		}

		public init(draft: Combo.Draft) {
			self.draft = draft
			let comboIDs = draft.id.map { [$0] } ?? []
			_memberships = FetchAll(ComboList.where { $0.comboID.in(comboIDs) })
			// Empty first and then seeded, because reading `memberships` goes through `self`
			// and Swift will not lend it out until every stored property has a value. The
			// query above has already run by then — a `@FetchAll` fetches as it is built.
			selectedListIDs = []
			selectedListIDs = Set(memberships.map(\.listID))
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
				let listIDs = state.selectedOptions.map(\.id)

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
/// The reconciliation deletes what is no longer ticked and inserts what is newly ticked,
/// rather than deleting every row and reinserting: a membership nobody touched keeps its id
/// and its `createdAt`, so it does not resurface on every other device as a deletion
/// followed by a fresh insert.
///
/// **Duplicate rows for a still-ticked List are left exactly where they are.** Two devices
/// adding the same List offline is a legal steady state under ADR-0008, and deduplication
/// belongs where that ADR puts it — in the pool, when it is built. Collapsing them here
/// would mean a save issuing a hard, global delete of a row another device authored, which
/// is not something the user asked this form to do.
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

	try ComboList
		.inCombo(comboID)
		.and(ComboList.where { $0.listID.notIn(memberListIDs) })
		.delete()
		.execute(db)

	let keptListIDs = try Set(ComboList.inCombo(comboID).select { $0.listID }.fetchAll(db))
	let added = memberListIDs
		.filter { !keptListIDs.contains($0) }
		.map { ComboList.Draft(comboID: comboID, createdAt: now, listID: $0) }
	guard !added.isEmpty else { return }
	// One statement for the lot, rather than a prepare and a step per newly-ticked List.
	try ComboList.insert { added }.execute(db)
}

/// An upsert that wrote no row, which SQLite does not do — but `RETURNING` is typed as
/// optional, and the alternative to naming this is a force unwrap on the one statement the
/// whole save hangs off.
private struct ComboNotSaved: Error {}
