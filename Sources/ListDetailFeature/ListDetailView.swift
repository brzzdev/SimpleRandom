//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Models

/// One List's Items: inline title, `+` in the toolbar, tap to edit, swipe to delete.
public struct ListDetailView: View {
	@Bindable private var store: StoreOf<ListDetail>

	public init(store: StoreOf<ListDetail>) {
		self.store = store
	}

	public var body: some View {
		Group {
			if store.items.isEmpty {
				emptyState
			} else {
				items
			}
		}
		// The List's own name, so `verbatim` — it is the user's text, not a string to look up.
		.navigationTitle(Text(verbatim: store.list.name))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button {
				store.send(.newItemButtonTapped)
			} label: {
				Label { Text("New Item", bundle: #bundle) } icon: { Image(systemName: "plus") }
			}
		}
		.sheet(item: $store.scope(\.editor, action: \.editor)) { editorStore in
			ItemEditorView(store: editorStore)
		}
	}

	private var emptyState: some View {
		ContentUnavailableView {
			Label { Text("No Items", bundle: #bundle) } icon: { Image(systemName: "text.badge.plus") }
		} description: {
			Text("Add the things you want to pick between.", bundle: #bundle)
		}
	}

	private var items: some View {
		List {
			ForEach(store.items) { item in
				Button {
					store.send(.rowTapped(item))
				} label: {
					Text(verbatim: item.title)
						// Rows wrap and grow tall under Dynamic Type — they never clamp and never
						// truncate, which is correct for a list whose whole content is text the
						// user wrote (ADR-0018).
						.fixedSize(horizontal: false, vertical: true)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.buttonStyle(.plain)
				.swipeActions {
					Button(role: .destructive) {
						store.send(.deleteSwiped(item))
					} label: {
						Label { Text("Delete", bundle: #bundle) } icon: { Image(systemName: "trash") }
					}
				}
			}
		}
	}
}
