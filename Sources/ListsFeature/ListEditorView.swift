//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Components
internal import Models

/// The editor sheet, at a medium detent: name, emoji, draw mode.
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
		.presentationDetents([.medium])
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
