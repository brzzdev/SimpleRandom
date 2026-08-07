//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models

internal import Dependencies
internal import IssueReporting
internal import Preferences
internal import SQLiteData
internal import Sharing

/// The Settings tab: the one preference the app has, what the app is, and the one way to get
/// rid of everything.
///
/// Reads are the two `@FetchOne` counts below and the write goes straight to
/// `@Dependency(\.defaultDatabase)` inside `store.addTask`; nothing sits between this feature
/// and SQLiteData (ADR-0011).
///
/// **No `#if DEBUG` section here or in ``SettingsView``** — release and debug builds show the
/// same tab. `Sync` and `View Logs` arrive with the CloudKit wiring (#29) and the log viewer
/// (#28), and the `Acknowledgements` row's destination with #27.
@Feature
public struct SettingsFeature {
	/// The question `Delete All Lists` asks before it goes ahead.
	///
	/// It carries both counts because the dialog states both — the specificity is the safety
	/// mechanism, and this delete is hard, global and unrecoverable. Captured when the button
	/// is tapped rather than read live while the dialog is up, so the numbers you answer for
	/// are the numbers you were shown.
	@Feature
	public struct ConfirmDeleteAll: Prompt {
		public struct State {
			public let itemCount: Int
			public let listCount: Int

			public init(itemCount: Int, listCount: Int) {
				self.itemCount = itemCount
				self.listCount = listCount
			}
		}

		public enum Action {
			case deleteButtonTapped
		}

		public init() {}
	}

	public struct State {
		public var confirmDeleteAll: ConfirmDeleteAll.State?

		/// The two counts the dialog states, and — for `listCount` — what the destructive row
		/// is disabled on. There is nothing to delete until there is something to delete.
		@FetchOne(Item.select { $0.id.count() }) internal var itemCount = 0
		@FetchOne(Models.List.select { $0.id.count() }) internal var listCount = 0

		@Shared(.theme) internal var theme: Theme

		/// Fixed for the life of the process, so a `let` read once rather than a `Bundle`
		/// lookup every time the view's body runs.
		internal let version = AppVersion.current

		public init() {}
	}

	public enum Action {
		case confirmDeleteAll(ConfirmDeleteAll.Action)
		case deleteAllListsButtonTapped
	}

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .confirmDeleteAll(.deleteButtonTapped):
				deleteAllLists()

			case .deleteAllListsButtonTapped:
				state.confirmDeleteAll = ConfirmDeleteAll.State(
					itemCount: state.itemCount,
					listCount: state.listCount,
				)
			}
		}
		.ifLet(\.confirmDeleteAll, action: \.confirmDeleteAll) { ConfirmDeleteAll() }
	}

	/// Deletes every List and, through the schema's cascades, every Item, every Combo
	/// membership and both kinds of draw row.
	///
	/// **Combos themselves stay**, exactly as they do when one List is deleted: a Combo is an
	/// arrangement of Lists rather than an owner of them, and the gesture is `Delete All
	/// Lists`. They silently shrink to empty, which is what a Combo losing a member always
	/// does.
	///
	/// There is no local-only variant. Deletes here are hard and sync-propagating, and
	/// stopping the engine to wipe locally only means CloudKit re-seeds the device on restart.
	private func deleteAllLists() {
		@Dependency(\.defaultDatabase) var database
		store.addTask {
			await withErrorReporting {
				try await database.write { db in
					try Models.List.delete().execute(db)
				}
			}
		}
	}
}
