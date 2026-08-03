//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models

internal import Dependencies
internal import Foundation
internal import IssueReporting
internal import SQLiteData

/// The editor sheet: name, emoji and draw mode, over a `List.Draft`.
///
/// One feature covers both create and rename because a draft is exactly the difference — a
/// new List is a draft whose `id` is `nil` and which the database will key on insert, a
/// rename is a draft carrying the id it already had. `upsert` then does the right thing
/// without the editor having to know which it is.
@Feature
public struct ListEditor {
	public struct State {
		public var draft: Models.List.Draft

		/// Trimmed and non-empty is the rule for a name; this is where it is enforced, and
		/// the only thing gating Save. The emoji gates nothing.
		public var isSavable: Bool { !draft.name.trimmedForStorage.isEmpty }

		public init(draft: Models.List.Draft) {
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
				// second row rather than updating the first — and two Lists with one name is
				// legal here, so it would land silently.
				//
				// Untested for the reason ``ItemEditor`` gives: a `TestStore` cannot stage the
				// race, and the test that looks like it does passes without the guard.
				guard state.isSavable, !save.isRunning else { return }
				var edited = state.draft
				edited.name = edited.name.trimmedForStorage
				let draft = edited

				@Dependency(\.defaultDatabase) var database
				store.addTask(id: save) {
					// `withErrorReporting` reports the failure and returns `nil`. The sheet
					// stays up when it does: dismissing would throw the draft away and leave
					// the user believing it saved, which is the one outcome worse than the
					// write failing.
					// `Void?` is spelled out because the closure returns nothing, and an
					// inferred `()?` is a warning.
					let saved: Void? = await withErrorReporting {
						try await database.write { db in
							try Models.List.upsert { draft }.execute(db)
						}
					}
					guard saved != nil else { return }
					try store.dismiss()
				}
			}
		}
	}
}
