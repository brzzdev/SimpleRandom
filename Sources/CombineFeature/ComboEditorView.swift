//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Components
internal import Models

/// The one form: name, emoji, draw mode and the membership checklist, in a single sheet.
///
/// The same sheet creates and edits — see ``ComboEditor`` — so its title is the only thing
/// that tells the two apart.
public struct ComboEditorView: View {
	@Bindable private var store: StoreOf<ComboEditor>

	public init(store: StoreOf<ComboEditor>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField(text: $store.draft.name) { Text("Name", bundle: #bundle) }
					EmojiField(emoji: $store.draft.emoji)
				}

				Section {
					Picker(selection: $store.draft.drawMode) {
						ForEach(DrawMode.allCases, id: \.self) { mode in
							mode.title.tag(mode)
						}
					} label: {
						Text("Draw mode", bundle: #bundle)
					}
					.pickerStyle(.segmented)
				} footer: {
					// The Deck footer says what a Combo's Deck does *not* touch, because nothing
					// else on this screen would: a Combo pools every Item of every member List
					// regardless of what that List has dealt, and drawing here never writes a
					// `ListDraw` row (ADR-0007).
					switch store.draft.drawMode {
					case .deck:
						Text(
							"Deals each item once, then offers a reshuffle. This Combo's Deck is separate from each List's own.",
							bundle: #bundle,
						)

					case .independent:
						Text("Picks at random every time. Repeats are possible.", bundle: #bundle)
					}
				}

				membership
			}
			.navigationTitle(store.draft.id == nil ? newTitle : editTitle)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						store.send(.cancelButtonTapped)
					} label: {
						Text("Cancel", bundle: #bundle)
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button {
						store.send(.saveButtonTapped)
					} label: {
						Text("Save", bundle: #bundle)
					}
					.disabled(!store.isSavable)
				}
			}
		}
		// `.large` alone, where the List editor opens at `.medium` and offers `.large`. This
		// sheet's last section is a row per List and so has no natural height at all — opening
		// at medium would put the app's longest scrolling content in the app's shortest sheet,
		// and the live footer that section is answering would start off screen.
		.presentationDetents([.large])
	}

	/// The membership checklist, and the live footer that is the point of it.
	///
	/// Membership has exactly one home — there is no separate picker sheet and no
	/// swipe-to-remove — which is what lets a Combo be a single Save (ADR-0020).
	private var membership: some View {
		Section {
			ForEach(store.options) { option in
				let isSelected = store.selectedListIDs.contains(option.id)
				Button {
					store.send(.listToggled(option))
				} label: {
					HStack {
						IndexRow(
							emoji: option.list.emoji,
							name: option.list.name,
							caption: option.caption,
							accessibilityLabel: option.accessibilityLabel,
						)

						if isSelected {
							Image(systemName: "checkmark")
								.foregroundStyle(.tint)
								// Decoration. The row carries the **Selected** trait below, and the
								// symbol would otherwise announce itself alongside it.
								.accessibilityHidden(true)
						}
					}
					// `.plain` hit-tests the label's drawn content, so without this the tap target
					// is the glyphs and the checkmark's column is dead on every unticked List.
					.contentShape(.rect)
				}
				.buttonStyle(.plain)
				// Selection *is* a trait here, unlike a dealt Item on the Lists tab: ticking a
				// List is exactly what `.isSelected` says it is (ADR-0018).
				.accessibilityAddTraits(isSelected ? .isSelected : [])
			}
		} header: {
			Text("Lists", bundle: #bundle)
		} footer: {
			// Live, and the only thing on the screen that says what a Combo will actually draw
			// from — the row captions are per List, and the pool is the sum (ADR-0020).
			//
			// Which of the two it is was decided in `State`, so this renders and chooses
			// nothing: the choice is a property a test can assert rather than a branch only a
			// running screen could check.
			switch store.poolFooter {
			case .pool(let count):
				Text("^[\(count) items](inflect: true) in the pool.", bundle: #bundle)

			case .prompt:
				Text("Pick the Lists to draw from.", bundle: #bundle)
			}
		}
	}

	private var editTitle: Text { Text("Edit Combo", bundle: #bundle) }
	private var newTitle: Text { Text("New Combo", bundle: #bundle) }
}

extension DrawMode {
	/// The user's word for each mode. `independent` is the schema's word and is never shown:
	/// "Plain" is what the Deck it sits opposite makes it mean.
	///
	/// Authored again rather than shared with the Lists tab, because the two tabs are peers
	/// and a string belongs to the catalogue of the target that renders it (ADR-0022).
	internal var title: Text {
		switch self {
		case .deck: Text("Deck", bundle: #bundle)
		case .independent: Text("Plain", bundle: #bundle)
		}
	}
}
