//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import ListDetailFeature
public import Models

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// The Lists index: every List you have made, and the gestures that create, rename and
/// delete them.
///
/// Reads are the `@FetchAll` below and writes go straight to `@Dependency(\.defaultDatabase)`
/// inside `store.addTask`; nothing sits between this feature and SQLiteData (ADR-0011).
@Feature
public struct ListsFeature {
	/// The two things this screen puts in front of the index, as one optional so only one of
	/// them can be up at a time.
	@Feature
	public enum Destination {
		case confirmDeletion(ConfirmDeletion)
		case editor(ListEditor)
	}

	/// The confirmation a non-empty List raises before it goes.
	///
	/// It carries the name and the count because the dialog states both — the specificity is
	/// the safety mechanism, and a delete here is hard, global and unrecoverable.
	@Feature
	public struct ConfirmDeletion: Prompt {
		public struct State {
			public let itemCount: Int
			public let listID: Models.List.ID
			public let name: String

			public init(itemCount: Int, listID: Models.List.ID, name: String) {
				self.itemCount = itemCount
				self.listID = listID
				self.name = name
			}
		}

		public enum Action {
			case deleteButtonTapped
		}

		public init() {}
	}

	public struct State {
		public var destination: Destination.State?
		public var detail: ListDetail.State?
		@FetchAll(ListSummary.index) internal var summaries: [ListSummary]

		public init() {}
	}

	public enum Action {
		case deleteSwiped(ListSummary)
		case destination(Destination.Action)
		case detail(ListDetail.Action)
		case editSwiped(ListSummary)
		case newListButtonTapped
		case rowTapped(ListSummary)
	}

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .deleteSwiped(let summary):
				// An empty List goes immediately — there is nothing in it to lose, and a
				// confirmation on every delete is what teaches people to tap through them.
				if summary.itemCount == 0 {
					delete(summary.id)
				} else {
					state.destination = .confirmDeletion(
						ConfirmDeletion.State(
							itemCount: summary.itemCount,
							listID: summary.id,
							name: summary.list.name,
						)
					)
				}

			case .destination(.confirmDeletion(.deleteButtonTapped)):
				guard let listID = state.destination?.confirmDeletion?.listID else { break }
				delete(listID)

			case .destination:
				break

			case .detail:
				break

			case .editSwiped(let summary):
				state.destination = .editor(ListEditor.State(draft: Models.List.Draft(summary.list)))

			case .newListButtonTapped:
				@Dependency(\.date.now) var now
				// Stamped when the sheet opens rather than when it is saved: `createdAt` is
				// the sort key, so a List's place in the index is the moment you started
				// making it. Nothing else reads it in v1.
				state.destination = .editor(
					ListEditor.State(
						draft: Models.List.Draft(createdAt: now, name: ""),
					)
				)

			case .rowTapped(let summary):
				state.detail = ListDetail.State(list: summary.list)
			}
		}
		.ifLet(\.destination, action: \.destination) { Destination.body }
		.ifLet(\.detail, action: \.detail) { ListDetail() }
	}

	/// Deletes a List and, through the schema's cascades, its Items and its Combo
	/// memberships.
	private func delete(_ listID: Models.List.ID) {
		@Dependency(\.defaultDatabase) var database
		store.addTask {
			await withErrorReporting {
				try await database.write { db in
					try Models.List.find(listID).delete().execute(db)
				}
			}
		}
	}
}
