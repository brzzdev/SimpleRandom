//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import SwiftUI

/// The Combine index with nothing in it — which is two different situations, and says two
/// different things.
///
/// With no Lists at all there is nothing to combine, and offering a `New Combo` button would
/// open a form whose checklist is empty; the copy sends you to the Lists tab instead, and the
/// toolbar's `+` is dimmed to match (ADR-0020). With Lists but no Combos it is the ordinary
/// empty index, and behaves like the Lists tab's: what a Combo is for, and a second way to
/// make one.
internal struct CombineEmptyState: View {
	private let store: StoreOf<CombineFeature>

	internal init(store: StoreOf<CombineFeature>) {
		self.store = store
	}

	internal var body: some View {
		if store.listCount == 0 {
			ContentUnavailableView {
				Label { Text("No Lists to Combine", bundle: #bundle) } icon: {
					Image(systemName: "rectangle.stack.badge.plus")
				}
			} description: {
				Text("Make a couple of Lists first, then combine them here.", bundle: #bundle)
			}
		} else {
			ContentUnavailableView {
				Label { Text("No Combos", bundle: #bundle) } icon: {
					Image(systemName: "rectangle.stack")
				}
			} description: {
				Text("Combine a few Lists and pick from all of them at once.", bundle: #bundle)
			} actions: {
				Button {
					store.send(.newComboButtonTapped)
				} label: {
					Text("New Combo", bundle: #bundle)
				}
				.buttonStyle(.borderedProminent)
			}
		}
	}
}
