//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import SwiftUI

/// The Lists index with nothing in it: what a List is for, and a second way to make one
/// beside the toolbar's `+`.
///
/// No seed content and no starter templates — a seeded List is real synced data the user has
/// to delete, on every device.
internal struct ListsEmptyState: View {
	private let store: StoreOf<ListsFeature>

	internal init(store: StoreOf<ListsFeature>) {
		self.store = store
	}

	internal var body: some View {
		ContentUnavailableView {
			Label { Text("No Lists", bundle: #bundle) } icon: { Image(systemName: "list.bullet.rectangle") }
		} description: {
			Text("Make a list of things to pick between — lunch spots, films, chores.", bundle: #bundle)
		} actions: {
			Button {
				store.send(.newListButtonTapped)
			} label: {
				Text("New List", bundle: #bundle)
			}
			.buttonStyle(.borderedProminent)
		}
	}
}
