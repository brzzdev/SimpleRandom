//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// `ListDetail` — one List's Items, and the gestures that add, edit and delete them (#20).
///
/// Both tabs push it, which is why it is a target of its own rather than part of the Lists
/// index: a Combo's member row pushes the *real* List detail, and the screen cannot live
/// inside `ListsFeature` without `CombineFeature` importing the whole index to reach it
/// (ADR-0014).
///
/// The pinned Randomise bar is not here yet — it arrives with the draw in #21.
@Feature
public struct ListDetail {
	public struct State: Identifiable {
		public var editor: ItemEditor.State?
		@FetchAll internal var items: [Item]
		public let list: Models.List

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

			case .rowTapped(let item):
				state.editor = ItemEditor.State(draft: Item.Draft(item))
			}
		}
		.ifLet(\.editor, action: \.editor) { ItemEditor() }
	}
}
