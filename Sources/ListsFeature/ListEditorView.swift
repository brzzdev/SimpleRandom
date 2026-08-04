//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Components
internal import Models

/// The editor sheet, opening at a medium detent: name, emoji, draw mode.
///
/// The same sheet creates and renames — see ``ListEditor`` — so its title is the only thing
/// that tells the two apart.
public struct ListEditorView: View {
	@Bindable private var store: StoreOf<ListEditor>

	public init(store: StoreOf<ListEditor>) {
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
					switch store.draft.drawMode {
					case .deck:
						Text("Deals each item once, then offers a reshuffle.", bundle: #bundle)

					case .independent:
						Text("Picks at random every time. Repeats are possible.", bundle: #bundle)
					}
				}
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
		// Opens at medium, so nothing changes at default sizes — it gains somewhere to go. This
		// holds more than any other fixed-content sheet — name field, `EmojiField`, segmented
		// picker, footer paragraph, against one control each in the other two — and at the
		// largest accessibility size medium clips the footer off the bottom. `.large` is what
		// the user can then drag to (ADR-0018). The Combine tab's form holds more again, but
		// its last section is a row per List and so has no fixed height to check at all, which
		// is why that one opens at `.large` outright rather than offering it.
		//
		// **The keyboard is not the reason.** Checked on the simulator: iOS promotes the sheet
		// clear of the keyboard when the name field takes focus, and did so with `[.medium]`
		// alone — there is no narrow strip to type into, and no case here for opening at
		// `.large` rather than merely offering it.
		//
		// Not `RandomiseView`'s `isAccessibilitySize` conditional either: that sheet is fixed at
		// one detent because it is deliberately not resizable, whereas an editor being draggable
		// is unobjectionable at any size.
		.presentationDetents([.medium, .large])
	}

	private var editTitle: Text { Text("Edit List", bundle: #bundle) }
	private var newTitle: Text { Text("New List", bundle: #bundle) }
}

extension DrawMode {
	/// The user's word for each mode. `independent` is the schema's word and is never shown:
	/// "Plain" is what the Deck it sits opposite makes it mean.
	internal var title: Text {
		switch self {
		case .deck: Text("Deck", bundle: #bundle)
		case .independent: Text("Plain", bundle: #bundle)
		}
	}
}
