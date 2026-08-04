//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

/// The Combine tab: large title, `+`, no reorder and no search — the Lists tab's shape, over
/// Combos.
public struct CombineView: View {
	@Bindable private var store: StoreOf<CombineFeature>

	public init(store: StoreOf<CombineFeature>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Group {
				if store.summaries.isEmpty {
					CombineEmptyState(store: store)
				} else {
					CombineIndex(store: store)
				}
			}
			.navigationTitle(Text("Combine", bundle: #bundle))
			.toolbar {
				Button {
					store.send(.newComboButtonTapped)
				} label: {
					Label { Text("New Combo", bundle: #bundle) } icon: { Image(systemName: "plus") }
				}
				// There is nothing to combine until there is something to combine, and a form
				// whose only content is an empty checklist is worse than a dimmed `+`. The
				// empty state below says what to do instead (ADR-0020).
				.disabled(store.listCount == 0)
			}
			.navigationDestination(item: $store.scope(\.detail, action: \.detail)) { detailStore in
				ComboDetailView(store: detailStore)
			}
		}
		.sheet(item: $store.scope(\.destination, action: \.destination).editor) { editorStore in
			ComboEditorView(store: editorStore)
		}
	}
}
