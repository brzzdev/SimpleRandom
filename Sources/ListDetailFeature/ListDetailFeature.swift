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

/// `ListDetail` — one List's Items, the gestures that add, edit and delete them, and the
/// pinned Randomise that draws one (#20, #21).
///
/// Both tabs push it, which is why it is a target of its own rather than part of the Lists
/// index: a Combo's member row pushes the *real* List detail, and the screen cannot live
/// inside `ListsFeature` without `CombineFeature` importing the whole index to reach it
/// (ADR-0014). It behaves identically wherever it is pushed: drawing here draws from this
/// List alone and leaves a presenting Combo's own deck untouched.
@Feature
public struct ListDetail {
	public struct State: Identifiable {
		public var editor: ItemEditor.State?
		@FetchAll internal var items: [Item]
		public let list: Models.List
		public var randomise: RandomiseFeature.State?

		public var id: Models.List.ID { list.id }

		public init(list: Models.List) {
			self.list = list
			// Built here rather than declared on the property the way the index's is, because
			// the query is per-List and the id only exists once there is a List to read it
			// from.
			//
			// `(createdAt, id)` ascending is the app's one sort order. `createdAt` alone is not
			// a total order — two devices creating rows offline in the same second leave SQLite
			// to break the tie however it likes — and the primary key tie-break is arbitrary
			// but identical on every device.
			_items = FetchAll(Item.where { $0.listID.eq(list.id) }.order { ($0.createdAt, $0.id) })
		}
	}

	public enum Action {
		case deleteSwiped(Item)
		case editor(ItemEditor.Action)
		case newItemButtonTapped
		case randomise(RandomiseFeature.Action)
		case randomiseButtonTapped
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

			case .editor:
				break

			case .newItemButtonTapped:
				@Dependency(\.date.now) var now
				// Stamped when the sheet opens rather than when it is saved, as the List editor
				// does it: `createdAt` is the sort key, so an Item's place in the List is the
				// moment you started typing it.
				state.editor = ItemEditor.State(
					draft: Item.Draft(createdAt: now, listID: state.list.id, title: ""),
				)

			case .randomise:
				break

			case .randomiseButtonTapped:
				// The scope is all the sheet is handed: it owns the pool and the pick from here,
				// and it draws its opening result as it is built (ADR-0016).
				state.randomise = RandomiseFeature.State(scope: .list(state.list.id))

			case .rowTapped(let item):
				state.editor = ItemEditor.State(draft: Item.Draft(item))
			}
		}
		.ifLet(\.editor, action: \.editor) { ItemEditor() }
		.ifLet(\.randomise, action: \.randomise) { RandomiseFeature() }
	}
}
