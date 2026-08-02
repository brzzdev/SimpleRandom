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

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .cancelButtonTapped:
				store.addTask { try store.dismiss() }

			case .saveButtonTapped:
				// The same rule the Save button is gated on, asked of the state rather than
				// recomputed here, so the two cannot come to disagree.
				guard state.isSavable else { return }
				var edited = state.draft
				edited.title = edited.title.trimmedForStorage
				let draft = edited

				@Dependency(\.defaultDatabase) var database
				store.addTask {
					// `withErrorReporting` reports the failure and returns `nil`. The sheet stays
					// up when it does: dismissing would throw the draft away and leave the user
					// believing it saved, which is the one outcome worse than the write failing.
					let saved = await withErrorReporting {
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
