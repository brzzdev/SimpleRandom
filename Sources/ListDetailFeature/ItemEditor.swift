//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// The Item editor sheet: one field, over an `Item.Draft`.
///
/// One feature covers both add and edit because a draft is exactly the difference — a new
/// Item is a draft whose `id` is `nil` and which the database will key on insert, an edit is
/// a draft carrying the id it already had. `upsert` then does the right thing without the
/// editor having to know which it is.
@Feature
public struct ItemEditor {
	public struct State {
		public var draft: Item.Draft

		/// Trimmed and non-empty is the rule for a title; this is where it is enforced, and the
		/// only thing gating Save. Two Items may still share one, because repetition is the
		/// user's own weighting mechanism (ADR-0004).
		public var isSavable: Bool { !draft.title.trimmedForStorage.isEmpty }

		public init(draft: Item.Draft) {
			self.draft = draft
		}
	}

	public enum Action {
		case cancelButtonTapped
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

			case .saveButtonTapped:
				// The same rule the Save button is gated on, asked of the state rather than
				// recomputed here, so the two cannot come to disagree.
				//
				// And not a second time while the first write is still in flight. The draft's
				// id is still `nil` until the sheet dismisses, so a second `upsert` inserts a
				// second row rather than updating the first — and two Items with one title is
				// legal here, so it would land silently and quietly double that title's odds.
				//
				// Deliberately untested: a `TestStore` runs the first save's effect to
				// completion before it delivers the second action, so the sheet is already
				// dismissed and `.ifLet` drops the second tap. A test written against it
				// passes with this guard removed, which is worse than no test at all.
				guard state.isSavable, !save.isRunning else { return }
				var edited = state.draft
				edited.title = edited.title.trimmedForStorage
				let draft = edited

				@Dependency(\.defaultDatabase) var database
				store.addTask(id: save) {
					// `withErrorReporting` reports the failure and returns `nil`. The sheet stays
					// up when it does: dismissing would throw the draft away and leave the user
					// believing it saved, which is the one outcome worse than the write failing.
					//
					// `Void?` spelled out: the closure returns nothing, so this is only ever a
					// success flag, and an inferred `()?` is a warning rather than a type anyone
					// meant to write.
					let saved: Void? = await withErrorReporting {
						try await database.write { db in
							try Item.upsert { draft }.execute(db)
						}
					}
					guard saved != nil else { return }
					try store.dismiss()
				}
			}
		}
	}
}
