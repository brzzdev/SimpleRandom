//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// The Combine index: every Combo you have made, and the gestures that create, edit and
/// delete them (#23).
///
/// It mirrors the Lists index deliberately — same title treatment, same `+`, same swipes,
/// same `Components` row — and reads `Models.List` through its own queries rather than
/// depending on `ListsFeature`: the two tabs are peers, and neither imports the other
/// (ADR-0014).
///
/// Reads are the `@FetchAll` and `@FetchOne` below and writes go straight to
/// `@Dependency(\.defaultDatabase)` inside `store.addTask`; nothing sits between this
/// feature and SQLiteData (ADR-0011).
@Feature
public struct CombineFeature {
	/// The two things this screen puts in front of the index, as one optional so only one of
	/// them can be up at a time.
	@Feature
	public enum Destination {
		case confirmDeletion(ConfirmDeletion)
		case editor(ComboEditor)
	}

	/// The confirmation a Combo with members raises before it goes.
	///
	/// It carries the name because the alert states it, and nothing else: the message is the
	/// same sentence whatever the Combo holds. What a Combo loses is an *arrangement*, not
	/// content — the Lists in it are kept — so there is no count to make specific the way
	/// `Delete N Items` is on the Lists tab.
	@Feature
	public struct ConfirmDeletion: Prompt {
		public struct State {
			public let comboID: Combo.ID
			public let name: String

			public init(comboID: Combo.ID, name: String) {
				self.comboID = comboID
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

		/// How many Lists exist at all, which is what `+` and the second empty state are
		/// gated on — there is nothing to combine until there is something to combine
		/// (ADR-0020).
		///
		/// A count rather than the rows: the checklist itself is ``ComboEditor``'s to read,
		/// and this screen renders no List.
		@FetchOne(Models.List.select { $0.id.count() }) internal var listCount = 0

		/// Every membership, held only to seed the form when a row is edited.
		///
		/// The form needs the Combo's current members the instant the swipe lands, and a
		/// scoped query cannot be run from inside a reducer without going async and leaving
		/// the sheet up in front of a half-built state. So the index keeps the join table —
		/// a handful of rows per Combo, and one query rather than one per edit — and hands
		/// the relevant ids over.
		///
		/// `(createdAt, id)` ascending like everything else, so a reload cannot reshuffle the
		/// rows underneath an exhaustive assertion.
		@FetchAll(ComboList.all.order { ($0.createdAt, $0.id) })
		internal var memberships: [ComboList]

		@FetchAll(ComboSummary.index) internal var summaries: [ComboSummary]

		public init() {}
	}

	public enum Action {
		case deleteSwiped(ComboSummary)
		case destination(Destination.Action)
		case editSwiped(ComboSummary)
		case newComboButtonTapped
	}

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .deleteSwiped(let summary):
				// An empty Combo goes immediately — there is no arrangement in it to lose, and
				// a confirmation on every delete is what teaches people to tap through them.
				if summary.listCount == 0 {
					delete(summary.id)
				} else {
					state.destination = .confirmDeletion(
						ConfirmDeletion.State(comboID: summary.id, name: summary.combo.name)
					)
				}

			case .destination(.confirmDeletion(.deleteButtonTapped)):
				guard let comboID = state.destination?.confirmDeletion?.comboID else { break }
				delete(comboID)

			case .destination:
				break

			case .editSwiped(let summary):
				state.destination = .editor(
					ComboEditor.State(
						draft: Combo.Draft(summary.combo),
						selectedListIDs: state.memberListIDs(of: summary.id),
					)
				)

			case .newComboButtonTapped:
				@Dependency(\.date.now) var now
				// Stamped when the form opens rather than when it is saved, as the List editor
				// does it: `createdAt` is the sort key, so a Combo's place in the index is the
				// moment you started making it. Nothing else reads it in v1.
				state.destination = .editor(
					ComboEditor.State(draft: Combo.Draft(createdAt: now, name: ""))
				)
			}
		}
		.ifLet(\.destination, action: \.destination) { Destination.body }
	}

	/// Deletes a Combo and, through the schema's cascades, its memberships and its draw rows.
	/// The member Lists themselves are untouched — a Combo points at them and does not own
	/// them.
	private func delete(_ comboID: Combo.ID) {
		@Dependency(\.defaultDatabase) var database
		store.addTask {
			await withErrorReporting {
				try await database.write { db in
					try Combo.find(comboID).delete().execute(db)
				}
			}
		}
	}
}

extension CombineFeature.State {
	/// The Lists one Combo currently holds, deduplicated — two devices adding the same List
	/// offline leave two rows for it, and a form that reopened with it ticked twice would
	/// have nothing to say about the second (ADR-0008).
	internal func memberListIDs(of comboID: Combo.ID) -> Set<Models.List.ID> {
		Set(memberships.lazy.filter { $0.comboID == comboID }.map(\.listID))
	}
}
