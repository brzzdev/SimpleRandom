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
	/// **It carries the rows themselves, not just their counts.** The dialog states how much
	/// goes and the delete removes exactly that — the specificity is the safety mechanism, and
	/// a delete that exceeded the number on screen would break it. Counting at the tap and
	/// deleting "everything" later is not the same statement: a sync insert landing while the
	/// dialog is up would be swept up by a question that never mentioned it, and this delete
	/// is hard, global and unrecoverable.
	///
	/// Rows arriving in that window therefore survive, and the next tap counts them.
	///
	/// `itemCount` is the exception and stays a count: Items are not deleted directly but
	/// cascade from the Lists named here, so there is nothing to name.
	@Feature
	public struct ConfirmDeleteAll: Prompt {
		public struct State {
			public let comboIDs: [Combo.ID]
			public let itemCount: Int
			public let listIDs: [Models.List.ID]

			public var comboCount: Int { comboIDs.count }
			public var listCount: Int { listIDs.count }

			public init(comboIDs: [Combo.ID], itemCount: Int, listIDs: [Models.List.ID]) {
				self.comboIDs = comboIDs
				self.itemCount = itemCount
				self.listIDs = listIDs
			}
		}

		public enum Action {
			case deleteButtonTapped
		}

		public init() {}
	}

	public struct State {
		public var confirmDeleteAll: ConfirmDeleteAll.State?

		/// What the gesture would delete, which is what the dialog states and what the
		/// destructive row is disabled on — there is nothing to delete until there is something
		/// to delete.
		///
		/// Ids rather than counts for the two tables actually deleted, so the confirmation can
		/// carry the rows it is asking about. Items only cascade, so a count is all there is.
		@FetchAll(Combo.select { $0.id }) internal var comboIDs: [Combo.ID]
		@FetchOne(Item.select { $0.id.count() }) internal var itemCount = 0
		@FetchAll(Models.List.select { $0.id }) internal var listIDs: [Models.List.ID]

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
				guard let deletion = state.confirmDeleteAll else { break }
				deleteAll(comboIDs: deletion.comboIDs, listIDs: deletion.listIDs)

			case .deleteAllListsButtonTapped:
				state.confirmDeleteAll = ConfirmDeleteAll.State(
					comboIDs: state.comboIDs,
					itemCount: state.itemCount,
					listIDs: state.listIDs,
				)
			}
		}
		.ifLet(\.confirmDeleteAll, action: \.confirmDeleteAll) { ConfirmDeleteAll() }
	}

	/// Deletes the Lists and Combos the confirmation named and, through the schema's cascades,
	/// every Item, every membership and both kinds of draw row belonging to them.
	///
	/// **Combos go too.** This is the one gesture that gets rid of everything, so leaving them
	/// behind would leave the Combine tab holding rows that can no longer name what they were
	/// arrangements of. It is what separates this from deleting Lists one at a time, where a
	/// Combo stays and silently shrinks.
	///
	/// **By id rather than whole-table**, so what goes is what the dialog counted. Anything
	/// that arrives between the tap and this write — a sync insert, most plausibly — is not
	/// covered by the question that was asked, and survives to be counted by the next one.
	///
	/// One `write`, so it is one transaction: a delete that took the Lists and left the Combos
	/// would be a state neither answer to the dialog asked for. Each statement is skipped when
	/// its side is empty, because SQLite rejects an empty `IN ()`.
	///
	/// There is no local-only variant. Deletes here are hard and sync-propagating, and
	/// stopping the engine to wipe locally only means CloudKit re-seeds the device on restart.
	private func deleteAll(comboIDs: [Combo.ID], listIDs: [Models.List.ID]) {
		@Dependency(\.defaultDatabase) var database
		store.addTask {
			await withErrorReporting {
				try await database.write { db in
					if !listIDs.isEmpty {
						try Models.List.where { $0.id.in(listIDs) }.delete().execute(db)
					}
					if !comboIDs.isEmpty {
						try Combo.where { $0.id.in(comboIDs) }.delete().execute(db)
					}
				}
			}
		}
	}
}
