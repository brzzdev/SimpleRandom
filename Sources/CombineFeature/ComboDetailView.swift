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
			// One button, and the two things it can be, exactly as the Lists tab does it: a spent
			// Combo Deck reads **Reshuffle** and puts its own cards back, rather than opening a
			// sheet with nothing to show. Which of the two it is, is the bar's to decide — it is
			// handed both and picks with the same flag it picks the word with.
			.randomiseBar(
				caption: captions.read,
				spokenCaption: captions.spoken,
				isEnabled: store.canRandomise,
				isExhausted: store.isExhausted,
				randomise: { store.send(.randomiseButtonTapped) },
				reshuffle: { store.send(.reshuffleButtonTapped) },
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

	/// What sits under the button — the pool, a Deck running down, or which of the two things is
	/// missing — and what VoiceOver reads in its place, so the bar says
	/// `Randomise, Deck, 10 of 13 left, button`.
	///
	/// The Deck variant is authored twice because its separator differs: `·` is read and a comma
	/// is spoken (ADR-0022). The other three carry no separator to differ over, so each is one
	/// entry said once.
	///
	/// Which of the four it is was decided in `State`, so this renders and chooses nothing —
	/// the choice is a property a test can assert rather than a branch only a running screen
	/// could check.
	private var captions: (read: Text, spoken: Text) {
		switch store.randomiseCaption {
		case let .deck(remaining, total):
			// The Combine index row's Deck caption without its `N Lists`, which the row needs to
			// name the Combo it is one of and this screen's title has already said.
			return (
				Text("Deck · \(remaining) of \(total) left", bundle: #bundle),
				Text("Deck, \(remaining) of \(total) left", bundle: #bundle)
			)

		case .noItems:
			let prompt = Text("The Lists in this Combo have no items", bundle: #bundle)
			return (prompt, prompt)

		case .noLists:
			let prompt = Text("Add a List to randomise", bundle: #bundle)
			return (prompt, prompt)

		case .pool(let count):
			// Inflected, because plain interpolation renders "1 items" on screen for everyone
			// (ADR-0018). The Lists tab's enabled caption word for word: opening a Combo should
			// tell you nothing different about its pool from the way a List tells you about its
			// Items.
			let pool = Text("^[\(count) items](inflect: true)", bundle: #bundle)
			return (pool, pool)
		}
	}
}
