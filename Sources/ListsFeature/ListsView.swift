//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Components
internal import ListDetailFeature
internal import Models

public struct ListsView: View {
	@Bindable private var store: StoreOf<ListsFeature>

	public init(store: StoreOf<ListsFeature>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Group {
				if store.summaries.isEmpty {
					emptyState
				} else {
					index
				}
			}
			.navigationTitle(Text("Lists", bundle: #bundle))
			.toolbar {
				Button {
					store.send(.newListButtonTapped)
				} label: {
					Label { Text("New List", bundle: #bundle) } icon: { Image(systemName: "plus") }
				}
			}
			.navigationDestination(item: $store.scope(\.detail, action: \.detail)) { detailStore in
				ListDetailView(store: detailStore)
			}
		}
		.sheet(item: $store.scope(\.destination, action: \.destination).editor) { editorStore in
			ListEditorView(store: editorStore)
		}
		.confirmationDialog(
			deletionTitle,
			isPresented: isConfirmingDeletion,
			titleVisibility: .visible,
			presenting: pendingDeletion,
		) { deletion in
			Button(role: .destructive) {
				store.send(.destination(.confirmDeletion(.deleteButtonTapped)))
			} label: {
				Text("Delete ^[\(deletion.itemCount) Items](inflect: true)", bundle: #bundle)
			}
		} message: { _ in
			Text("This can't be undone, and it happens on your other devices too.", bundle: #bundle)
		}
	}

	private var emptyState: some View {
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

	private var index: some View {
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
	}

	/// The List the confirmation is about, if one is up.
	private var pendingDeletion: ListsFeature.ConfirmDeletion.State? {
		store.destination?.confirmDeletion
	}

	/// The dialog names the List it is about to destroy. The specificity is the safety
	/// mechanism: a delete here is hard, global and unrecoverable.
	private var deletionTitle: Text {
		// The name is lifted out rather than interpolated in place: a string literal inside
		// the interpolation would end the outer literal as far as the lint rule guarding
		// `bundle: #bundle` can see, and it would read the call as missing one.
		let name = pendingDeletion?.name ?? ""
		return Text("Delete “\(name)”?", bundle: #bundle)
	}

	/// SwiftUI's `confirmationDialog` has no `item:` form, so the presented value and the
	/// flag are derived separately from the same optional child state.
	private var isConfirmingDeletion: Binding<Bool> {
		let deletion = $store.scope(\.destination, action: \.destination).confirmDeletion
		return Binding(
			get: { deletion.wrappedValue != nil },
			set: { isPresented in
				guard !isPresented else { return }
				deletion.wrappedValue = nil
			},
		)
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
