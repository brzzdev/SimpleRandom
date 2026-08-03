//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import Models
internal import SwiftUI

/// One List's Items: title only, tap to edit, swipe to delete, and a checkmark on whatever
/// its Deck has dealt.
///
/// A `View` of its own rather than a computed property of ``ListDetailView``, because it is
/// not a fragment — it is a whole `List`, its `ForEach`, its rows, their swipe actions and
/// their accessibility treatment. A computed property re-evaluates with its parent and cannot
/// be diffed on its own.
internal struct ListDetailItems: View {
	private let store: StoreOf<ListDetail>

	internal init(store: StoreOf<ListDetail>) {
		self.store = store
	}

	internal var body: some View {
		// Built once for the whole List rather than per row, which a `Set` computed inside the
		// `ForEach` would be.
		let dealtItemIDs = store.dealtItemIDs

		List {
			ForEach(store.items) { item in
				let isDealt = dealtItemIDs.contains(item.id)
				Button {
					store.send(.rowTapped(item))
				} label: {
					HStack {
						Text(verbatim: item.title)
							// Rows wrap and grow tall under Dynamic Type — they never clamp and never
							// truncate, which is correct for a list whose whole content is text the
							// user wrote (ADR-0018).
							.fixedSize(horizontal: false, vertical: true)
							.frame(maxWidth: .infinity, alignment: .leading)

						// Secondary text *and* a checkmark, never colour alone: Differentiate
						// Without Colour needs nothing from this app because a dealt Item is
						// already legible without it (ADR-0018).
						if isDealt {
							Image(systemName: "checkmark")
								// Decoration. The row says "dealt" in its accessibility value, and
								// the symbol would otherwise announce itself alongside it.
								.accessibilityHidden(true)
						}
					}
					.foregroundStyle(isDealt ? .secondary : .primary)
				}
				.buttonStyle(.plain)
				// A **value**, not the `.isSelected` trait: that trait says "Selected", which is
				// the wrong word — nobody selected it, the deck dealt it (ADR-0018). An
				// undealt Item has no value at all rather than a spoken "not dealt".
				.accessibilityValue(isDealt ? Text("Dealt", bundle: #bundle) : Text(verbatim: ""))
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
