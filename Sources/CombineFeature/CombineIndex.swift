//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import Components
internal import Models
internal import SwiftUI
internal import SwiftUINavigation

/// Every Combo you have made: emoji · name · counts, a leading swipe to edit and a trailing
/// one to delete.
///
/// A `View` of its own rather than a computed property of ``CombineView``, for the reason
/// `ListsIndex` is one: it is a whole `List`, its `ForEach`, its rows, their swipe actions
/// and their accessibility treatment, and a computed property re-evaluates with its parent
/// and cannot be diffed on its own.
///
/// Rows do not push anything yet. A Combo's detail screen — read-only membership and the
/// pinned Randomise — is #24, and a row that opened nothing would be worse than a row that
/// does not claim to.
///
/// The deletion confirmation hangs here rather than on ``CombineView``'s root, for the reason
/// `ListsIndex` gives: inside the navigation hierarchy and beside the rows that raise it, and
/// not on the row, because the scoped binding is nil-or-not rather than identity-matched and
/// every row in the `ForEach` would try to present at once.
internal struct CombineIndex: View {
	@Bindable private var store: StoreOf<CombineFeature>

	internal init(store: StoreOf<CombineFeature>) {
		self.store = store
	}

	internal var body: some View {
		List {
			ForEach(store.summaries) { summary in
				IndexRow(
					emoji: summary.combo.emoji,
					name: summary.combo.name,
					caption: summary.caption,
					accessibilityLabel: summary.accessibilityLabel,
				)
				.swipeActions(edge: .leading) {
					Button {
						store.send(.editSwiped(summary))
					} label: {
						Label { Text("Edit", bundle: #bundle) } icon: { Image(systemName: "pencil") }
					}
					.tint(.blue)
				}
				.swipeActions {
					// Deliberately not `role: .destructive`, for the reason `ListsIndex` gives:
					// inside `swipeActions` the role is a claim rather than a colour, and SwiftUI
					// animates the row out on tap without waiting to be told. This tap does not
					// always delete — a Combo with members gets the confirmation instead — so the
					// row would collapse and spring back while the question was still being asked.
					Button {
						store.send(.deleteSwiped(summary))
					} label: {
						Label { Text("Delete", bundle: #bundle) } icon: { Image(systemName: "trash") }
					}
					.tint(.red)
				}
			}
		}
		// The alert names the Combo it is about to destroy, and says what survives it. A delete
		// here is hard, global and unrecoverable — but what it destroys is an *arrangement*,
		// which is why the message is reassurance where the Lists tab's is a warning.
		//
		// `item:` is SwiftUINavigation's, not SwiftUI's — it takes the one optional the child
		// state already is and derives the presentation flag from it internally, so there is no
		// second `Binding<Bool>` to keep in step and nothing to unwrap at the call site.
		.alert(
			item: $store.scope(\.destination, action: \.destination).confirmDeletion,
		) { deletion in
			Text("Delete “\(deletion.name)”?", bundle: #bundle)
		} actions: { _ in
			Button(role: .destructive) {
				store.send(.destination(.confirmDeletion(.deleteButtonTapped)))
			} label: {
				Text("Delete", bundle: #bundle)
			}
			// Spelled out because an alert, unlike a confirmation dialog, supplies a dismiss
			// button of its own only when the actions builder is empty — without this the
			// question would have an answer but no way to decline it. No action to send: the
			// `item:` binding above nils the destination on dismiss.
			Button(role: .cancel) {} label: {
				Text("Cancel", bundle: #bundle)
			}
		} message: { _ in
			Text("The Lists in it are kept. This happens on your other devices too.", bundle: #bundle)
		}
	}
}

extension ComboSummary {
	/// What the row reads: `3 Lists · 12 items`, or `3 Lists · Deck · 10 of 13 left`.
	///
	/// Counts rather than member names, which read better and were the alternative: counts
	/// mirror the Lists tab, and they are the only option that shows a Combo's Deck running
	/// down without opening it (ADR-0020).
	///
	/// Each variant is one catalogue entry, `·` included, rather than fragments joined in
	/// Swift — a join is the one construction that cannot be translated, because the
	/// translator receives clauses with no control over word order and the separator is a
	/// punctuation decision made by someone thinking in English (ADR-0022).
	internal var caption: Text {
		switch combo.drawMode {
		case .deck:
			Text(
				"^[\(listCount) Lists](inflect: true) · Deck · \(remainingCount) of \(itemCount) left",
				bundle: #bundle,
			)

		case .independent:
			Text(
				"^[\(listCount) Lists](inflect: true) · ^[\(itemCount) items](inflect: true)",
				bundle: #bundle,
			)
		}
	}

	/// What VoiceOver reads: `Friday night, 3 Lists, 12 items`, or `Friday night, 3 Lists,
	/// Deck, 10 of 13 left`.
	///
	/// Authored separately from ``caption`` rather than derived from it, because the spoken
	/// separator is a comma and the name is inside the phrase rather than beside it.
	internal var accessibilityLabel: Text {
		switch combo.drawMode {
		case .deck:
			Text(
				"\(combo.name), ^[\(listCount) Lists](inflect: true), Deck, \(remainingCount) of \(itemCount) left",
				bundle: #bundle,
			)

		case .independent:
			Text(
				"\(combo.name), ^[\(listCount) Lists](inflect: true), ^[\(itemCount) items](inflect: true)",
				bundle: #bundle,
			)
		}
	}
}
