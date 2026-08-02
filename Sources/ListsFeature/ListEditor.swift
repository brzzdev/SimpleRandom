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

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .cancelButtonTapped:
				store.addTask { try store.dismiss() }

			case .saveButtonTapped:
				var edited = state.draft
				edited.name = edited.name.trimmedForStorage
				guard !edited.name.isEmpty else { return }
				let draft = edited

				@Dependency(\.defaultDatabase) var database
				store.addTask {
					await withErrorReporting {
						try await database.write { db in
							try Models.List.upsert { draft }.execute(db)
						}
					}
					try store.dismiss()
				}
			}
		}
	}
}

extension String {
	/// What goes in the `name` column: the user's text with the whitespace they did not mean
	/// to type taken off either end.
	internal var trimmedForStorage: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
