//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Components
internal import ListDetailFeature
internal import Models
internal import RandomiseFeature

/// One Combo's member Lists: inline title, `Edit` in the toolbar, tap a member to push the
/// real List detail, and the pinned Randomise that draws from the pool.
public struct ComboDetailView: View {
	@Bindable private var store: StoreOf<ComboDetail>

	public init(store: StoreOf<ComboDetail>) {
		self.store = store
	}

	public var body: some View {
		ComboMembers(store: store)
			// The Combo's own name, so `verbatim` — it is the user's text, not a string to look up.
			.navigationTitle(Text(verbatim: store.combo.name))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				// The only toolbar item. There is no `+` here and no swipe-to-remove on the rows:
				// membership has exactly one home, and it is the form this opens (ADR-0020).
				Button {
					store.send(.editButtonTapped)
				} label: {
					Text("Edit", bundle: #bundle)
				}
			}
			// Over an empty membership as well as over the rows: zero member Lists is legal — you
			// have just made the Combo — and its Randomise is visible but disabled, with a prompt
			// to add one rather than a button that has quietly gone away.
			//
			// `isExhausted` is `false` throughout: a Combo's own deck state is #25, so nothing
			// here can be spent and the bar never becomes **Reshuffle**. `reshuffle` is the
			// closure that word would call, and until then nothing calls it.
			.randomiseBar(
				caption: caption,
				spokenCaption: caption,
				isEnabled: store.canRandomise,
				isExhausted: false,
				randomise: { store.send(.randomiseButtonTapped) },
				reshuffle: {},
			)
			// The third level of optional child state, and the same `.navigationDestination(item:)`
			// the Lists tab pushes its detail with — no `[Path.State]` stack is introduced
			// (ADR-0013).
			.navigationDestination(item: $store.scope(\.detail, action: \.detail)) { detailStore in
				ListDetailView(store: detailStore)
			}
			// Two case key paths off one optional. The modifiers still chain, because only one
			// case can be non-`nil` — which is the whole point of ``ComboDetail/Destination``.
			.sheet(
				item: $store.scope(\.destination, action: \.destination).editor,
				content: ComboEditorView.init,
			)
			.sheet(
				item: $store.scope(\.destination, action: \.destination).randomise,
				content: RandomiseView.init,
			)
	}

	/// What sits under the button — the pool, or which of the two things is missing.
	///
	/// One `Text` serving both the read and the spoken caption, unlike the Lists tab's Deck
	/// variant: none of these three carries a separator, and `·` against a comma is the only
	/// thing that ever makes a caption two authored strings instead of one (ADR-0022).
	///
	/// Which of the three it is was decided in `State`, so this renders and chooses nothing —
	/// the choice is a property a test can assert rather than a branch only a running screen
	/// could check.
	private var caption: Text {
		switch store.randomiseCaption {
		case .noItems:
			Text("The Lists in this Combo have no items", bundle: #bundle)

		case .noLists:
			Text("Add a List to randomise", bundle: #bundle)

		case .pool(let count):
			// Inflected, because plain interpolation renders "1 items" on screen for everyone
			// (ADR-0018). The Lists tab's enabled caption word for word: opening a Combo should
			// tell you nothing different about its pool from the way a List tells you about its
			// Items.
			Text("^[\(count) items](inflect: true)", bundle: #bundle)
		}
	}
}
