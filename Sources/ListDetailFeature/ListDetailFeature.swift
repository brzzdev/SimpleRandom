//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models
public import RandomiseFeature

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// `ListDetail` — one List's Items, the gestures that add, edit and delete them, the pinned
/// Randomise that draws one, and a Deck's running count of what it has left (#20, #21, #22).
///
/// Both tabs push it, which is why it is a target of its own rather than part of the Lists
/// index: a Combo's member row pushes the *real* List detail, and the screen cannot live
/// inside `ListsFeature` without `CombineFeature` importing the whole index to reach it
/// (ADR-0014). It behaves identically wherever it is pushed: drawing here draws from this
/// List alone and leaves a presenting Combo's own deck untouched.
@Feature
public struct ListDetail {
	/// The two sheets this screen puts over the Items, as one optional so only one of them
	/// can be up at a time.
	///
	/// The exclusion is the model's to state rather than the layout's to happen to produce:
	/// the randomise sheet covers the bar that opens it and the item editor covers the rows
	/// that open it, but neither of those is a guarantee.
	@Feature
	public enum Destination {
		case editor(ItemEditor)
		case randomise(RandomiseFeature)
	}

	public struct State: Identifiable {
		public var destination: Destination.State?

		/// What this List has dealt. Empty for a plain List, which writes none — and *not*
		/// empty for a Deck switched back to plain, whose rows are preserved so that switching
		/// back resumes where it left off.
		///
		/// A second query rather than a `@Selection` joining the counts onto each Item: the
		/// screen wants the whole set at once — for the caption's arithmetic as much as for the
		/// checkmarks — and one query per screen is not the per-row fan-out the index avoids.
		@FetchAll internal var draws: [ListDraw]
		@FetchAll internal var items: [Item]
		public let list: Models.List

		public var id: Models.List.ID { list.id }

		/// The Items this screen shows as dealt — secondary, with a trailing checkmark.
		///
		/// Empty for a plain List even when rows survive from a Deck it used to be. Those rows
		/// are kept so that switching back resumes where it left off, but a plain List draws
		/// over everything with no memory, so marking Items dealt would describe a state it is
		/// not in — and the caption beneath, `4 items`, would be saying the opposite.
		public var dealtItemIDs: Set<Item.ID> {
			guard isDeck else { return [] }
			return Set(draws.map(\.itemID))
		}

		public var isDeck: Bool { list.drawMode == .deck }

		/// A Deck that has dealt everything it has. The pinned button reads **Reshuffle** here.
		///
		/// An empty List is not exhausted — it has dealt nothing because it holds nothing, and
		/// its Randomise is disabled with a prompt to add something rather than an invitation
		/// to put back cards that were never dealt.
		public var isExhausted: Bool {
			isDeck && !items.isEmpty && remainingCount == 0
		}

		/// How many Items the Deck has left to deal. Meaningless for a plain List, which has no
		/// memory of what it has drawn.
		public var remainingCount: Int { items.count - draws.count }

		public init(list: Models.List) {
			self.list = list
			// Ordered like everything else, so that a reload cannot reshuffle the rows underneath
			// an exhaustive assertion. Nothing on screen reads a draw's own order.
			_draws = FetchAll(ListDraw.inList(list.id).order { ($0.createdAt, $0.itemID) })
			// Built here rather than declared on the property the way the index's is, because
			// the query is per-List and the id only exists once there is a List to read it
			// from.
			//
			// `(createdAt, id)` ascending is the app's one sort order. `createdAt` alone is not
			// a total order — two devices creating rows offline in the same second leave SQLite
			// to break the tie however it likes — and the primary key tie-break is arbitrary
			// but identical on every device.
			_items = FetchAll(Item.inList(list.id).order { ($0.createdAt, $0.id) })
		}
	}

	public enum Action {
		case deleteSwiped(Item)
		case destination(Destination.Action)
		case newItemButtonTapped
		case randomiseButtonTapped
		case reshuffleButtonTapped
		case rowTapped(Item)
	}

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .deleteSwiped(let item):
				// No confirmation. An Item is one line of text the user can retype, unlike a
				// List, which takes its Items with it.
				@Dependency(\.defaultDatabase) var database
				store.addTask {
					await withErrorReporting {
						try await database.write { db in
							try Item.find(item.id).delete().execute(db)
						}
					}
				}

			case .destination:
				break

			case .newItemButtonTapped:
				@Dependency(\.date.now) var now
				// Stamped when the sheet opens rather than when it is saved, as the List editor
				// does it: `createdAt` is the sort key, so an Item's place in the List is the
				// moment you started typing it.
				state.destination = .editor(
					ItemEditor.State(
						draft: Item.Draft(createdAt: now, listID: state.list.id, title: ""),
					)
				)

			case .randomiseButtonTapped:
				// The scope is all the sheet is handed: it owns the pool, the pick and the deal
				// from here (ADR-0016). The state is inert until `.ifLet` mounts it, which happens
				// before this `send` returns — so the opening result is drawn, and `drawToken`
				// moved, ahead of the sheet ever being presented.
				state.destination = .randomise(RandomiseFeature.State(scope: .list(state.list)))

			case .reshuffleButtonTapped:
				// Puts every dealt Item back, whether the Deck is spent or barely touched:
				// Reshuffle is available at any time. A hard delete of the whole set, which is
				// what makes it the exact inverse of the rows the draws wrote (ADR-0006).
				@Dependency(\.defaultDatabase) var database
				let listID = state.list.id
				store.addTask {
					await withErrorReporting {
						try await database.write { db in
							try ListDraw.inList(listID).delete().execute(db)
						}
					}
				}

			case .rowTapped(let item):
				state.destination = .editor(ItemEditor.State(draft: Item.Draft(item)))
			}
		}
		.ifLet(\.destination, action: \.destination) { Destination.body }
	}
}
