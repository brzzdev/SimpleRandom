//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import Components
internal import Models
internal import SwiftUI

/// A Combo's member Lists: emoji · name · `N items`, each row pushing that List's own detail.
///
/// A `View` of its own rather than a computed property of ``ComboDetailView``, for the reason
/// `ListsIndex` is one: it is a whole `List`, its `ForEach` and its rows, and a computed
/// property re-evaluates with its parent and cannot be diffed on its own.
///
/// **Counts only, never a member's own deck state.** A Combo pools every Item of every member
/// regardless of what that List has dealt, so `Deck · 2 of 5 left` here would promise the
/// Combo respects it (ADR-0007).
///
/// No swipe-to-remove, and the section footer is what says so: membership is edited in the
/// one form, and a second way to change it would be a second home for it (ADR-0020). A Combo
/// with no members renders the section's header and that footer and nothing between them,
/// which is the honest empty state — the pinned bar below is already prompting for a List.
///
/// Removing a List *there* takes this Combo's draws of its Items with it (ADR-0023), which is
/// the one thing the form does to deck state and the reason these rows can never show it.
internal struct ComboMembers: View {
	private let store: StoreOf<ComboDetail>

	internal init(store: StoreOf<ComboDetail>) {
		self.store = store
	}

	internal var body: some View {
		List {
			Section {
				ForEach(store.members) { member in
					IndexRowButton(
						emoji: member.list.emoji,
						name: member.list.name,
						caption: member.caption,
						accessibilityLabel: member.accessibilityLabel,
					) {
						store.send(.memberTapped(member))
					}
				}
			} header: {
				Text("Lists", bundle: #bundle)
			} footer: {
				Text("Tap Edit to change which Lists are in this Combo.", bundle: #bundle)
			}
		}
	}
}
