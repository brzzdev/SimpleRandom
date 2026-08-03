//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Components
internal import Models
internal import RandomiseFeature

/// One List's Items: inline title, `+` in the toolbar, tap to edit, swipe to delete, and the
/// pinned Randomise that draws one.
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
			// A Deck only, and the one place Reshuffle is reachable mid-deck: the pinned button
			// does not become Reshuffle until the Deck is spent, and the sheet offers it only
			// once a re-roll has landed on exhaustion. Dimmed while there is nothing to put
			// back, which is the caption's `Deck · N of N left` said as a button state.
			if store.isDeck {
				Button {
					store.send(.reshuffleButtonTapped)
				} label: {
					Label { Text("Reshuffle", bundle: #bundle) } icon: { Image(systemName: "shuffle") }
				}
				.disabled(store.draws.isEmpty)
			}

			Button {
				store.send(.newItemButtonTapped)
			} label: {
				Label { Text("New Item", bundle: #bundle) } icon: { Image(systemName: "plus") }
			}
		}
		// Over the empty state as well as over the Items: an empty List is legal — you have just
		// made it — and its Randomise is visible but disabled, with a prompt to add something
		// rather than a button that has quietly gone away.
		//
		// One button, and the two things it can be: an exhausted Deck reads **Reshuffle** and
		// puts the cards back, rather than opening a sheet with nothing to show. Which of the
		// two it is, is the bar's to decide — it is handed both and picks with the same flag it
		// picks the word with.
		.randomiseBar(
			caption: randomiseCaptions.read,
			spokenCaption: randomiseCaptions.spoken,
			isEnabled: !store.items.isEmpty,
			isExhausted: store.isExhausted,
			randomise: { store.send(.randomiseButtonTapped) },
			reshuffle: { store.send(.reshuffleButtonTapped) },
		)
		.sheet(item: $store.scope(\.editor, action: \.editor)) { editorStore in
			ItemEditorView(store: editorStore)
		}
		.sheet(item: $store.scope(\.randomise, action: \.randomise)) { randomiseStore in
			RandomiseView(store: randomiseStore)
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
		// Built once for the whole List rather than per row, which a `Set` computed inside the
		// `ForEach` would be.
		let dealtItemIDs = store.dealtItemIDs

		return List {
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

	/// What sits under the button — `4 items`, `Deck · 10 of 13 left`, or why it is dimmed —
	/// and what VoiceOver reads in its place, so the bar says
	/// `Randomise, Deck, 10 of 13 left, button`.
	///
	/// Each variant is one catalogue entry rather than fragments joined in Swift — a join is
	/// the one construction that cannot be translated (ADR-0022) — and the count is inflected,
	/// because plain interpolation renders "1 items" on screen for everyone (ADR-0018). The
	/// Deck's is authored twice because its separator differs: `·` is read and a comma is
	/// spoken. The two with no separator to differ over are one entry, said once.
	///
	/// Both come off the same branch rather than two that have to agree, and the Deck's wording
	/// is the index row's word for word, so that opening a List tells you nothing different
	/// from the row you opened it from.
	private var randomiseCaptions: (read: Text, spoken: Text) {
		if store.items.isEmpty {
			let prompt = Text("Add an item to randomise", bundle: #bundle)
			return (prompt, prompt)
		}

		if store.isDeck {
			return (
				Text("Deck · \(store.remainingCount) of \(store.items.count) left", bundle: #bundle),
				Text("Deck, \(store.remainingCount) of \(store.items.count) left", bundle: #bundle)
			)
		}

		let count = Text("^[\(store.items.count) items](inflect: true)", bundle: #bundle)
		return (count, count)
	}
}
