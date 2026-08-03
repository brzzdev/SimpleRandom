//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import Components
internal import Models
internal import SwiftUI
internal import SwiftUINavigation

/// Every List you have made: emoji · name · caption, a leading swipe to rename and a
/// trailing one to delete.
///
/// A `View` of its own rather than a computed property of ``ListsView``, because it is not a
/// fragment — it is a whole `List`, its `ForEach`, its rows, their swipe actions and their
/// accessibility treatment. A computed property re-evaluates with its parent and cannot be
/// diffed on its own.
///
/// The deletion confirmation hangs here rather than on ``ListsView``'s root, which puts it
/// inside the navigation hierarchy and beside the rows that raise it. Not on the row: the
/// scoped binding below is nil-or-not rather than identity-matched, so every row in the
/// `ForEach` would see the same non-`nil` value and each would try to present.
internal struct ListsIndex: View {
	@Bindable private var store: StoreOf<ListsFeature>

	internal init(store: StoreOf<ListsFeature>) {
		self.store = store
	}

	internal var body: some View {
		List {
			ForEach(store.summaries) { summary in
				Button {
					store.send(.rowTapped(summary))
				} label: {
					IndexRow(
						emoji: summary.list.emoji,
						name: summary.list.name,
						caption: summary.caption,
						accessibilityLabel: summary.accessibilityLabel,
					)
				}
				.buttonStyle(.plain)
				.swipeActions(edge: .leading) {
					Button {
						store.send(.editSwiped(summary))
					} label: {
						Label { Text("Edit", bundle: #bundle) } icon: { Image(systemName: "pencil") }
					}
					.tint(.blue)
				}
				.swipeActions {
					Button(role: .destructive) {
						store.send(.deleteSwiped(summary))
					} label: {
						Label { Text("Delete", bundle: #bundle) } icon: { Image(systemName: "trash") }
					}
				}
			}
		}
		// The dialog names the List it is about to destroy, and states how much goes with it.
		// The specificity is the safety mechanism: a delete here is hard, global and
		// unrecoverable.
		//
		// `item:` is SwiftUINavigation's, not SwiftUI's — it takes the one optional the child
		// state already is and derives the presentation flag from it internally, so there is no
		// second `Binding<Bool>` to keep in step and nothing to unwrap at the call site.
		.confirmationDialog(
			item: $store.scope(\.destination, action: \.destination).confirmDeletion,
			titleVisibility: .visible,
		) { deletion in
			Text("Delete “\(deletion.name)”?", bundle: #bundle)
		} actions: { deletion in
			Button(role: .destructive) {
				store.send(.destination(.confirmDeletion(.deleteButtonTapped)))
			} label: {
				Text("Delete ^[\(deletion.itemCount) Items](inflect: true)", bundle: #bundle)
			}
		} message: { _ in
			Text("This can't be undone, and it happens on your other devices too.", bundle: #bundle)
		}
	}
}

extension ListSummary {
	/// What the row reads: `4 items`, or `Deck · 10 of 13 left`.
	///
	/// Each variant is one catalogue entry, `·` included, rather than fragments joined in
	/// Swift — a join is the one construction that cannot be translated, because the
	/// translator receives clauses with no control over word order and the separator is a
	/// punctuation decision made by someone thinking in English (ADR-0022).
	internal var caption: Text {
		switch list.drawMode {
		case .deck:
			Text("Deck · \(remainingCount) of \(itemCount) left", bundle: #bundle)

		case .independent:
			Text("^[\(itemCount) items](inflect: true)", bundle: #bundle)
		}
	}

	/// What VoiceOver reads: `Lunch, 4 items`, or `Lunch, Deck, 10 of 13 left`.
	///
	/// Authored separately from ``caption`` rather than derived from it, because the spoken
	/// separator is a comma and the name is inside the phrase rather than beside it.
	internal var accessibilityLabel: Text {
		switch list.drawMode {
		case .deck:
			Text("\(list.name), Deck, \(remainingCount) of \(itemCount) left", bundle: #bundle)

		case .independent:
			Text("\(list.name), ^[\(itemCount) items](inflect: true)", bundle: #bundle)
		}
	}
}
