//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import ListDetailFeature

public struct ListsView: View {
	@Bindable private var store: StoreOf<ListsFeature>

	public init(store: StoreOf<ListsFeature>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Group {
				if store.summaries.isEmpty {
					ListsEmptyState(store: store)
				} else {
					ListsIndex(store: store)
				}
			}
			.navigationTitle(Text("Lists", bundle: #bundle))
			.toolbar {
				Button {
					store.send(.newListButtonTapped)
				} label: {
					Label { Text("New List", bundle: #bundle) } icon: { Image(systemName: "plus") }
				}
			}
			.navigationDestination(item: $store.scope(\.detail, action: \.detail)) { detailStore in
				ListDetailView(store: detailStore)
			}
		}
		.sheet(item: $store.scope(\.destination, action: \.destination).editor) { editorStore in
			ListEditorView(store: editorStore)
		}
	}
}
