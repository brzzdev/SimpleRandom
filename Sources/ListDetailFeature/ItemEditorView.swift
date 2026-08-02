//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

// `Item.Draft.id` is what tells an add from an edit, and `MemberImportVisibility` means
// reaching a member of a type declared elsewhere needs that module imported here by name.
internal import Models

/// The Item editor sheet, at a short detent: one field and nothing else.
///
/// The same sheet adds and edits — see ``ItemEditor`` — so its title is the only thing that
/// tells the two apart.
public struct ItemEditorView: View {
	@Bindable private var store: StoreOf<ItemEditor>

	public init(store: StoreOf<ItemEditor>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			Form {
				TextField(text: $store.draft.title) { Text("Title", bundle: #bundle) }
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
		// Short, because one field is all there is — but `.large` is offered alongside it so
		// that a title set in an accessibility size has somewhere to go. A fixed height is the
		// one detent that does not grow with the type size, and trapping the field inside it
		// would be the sort of clamping ADR-0018 rules out.
		.presentationDetents([.height(220), .large])
	}

	private var editTitle: Text { Text("Edit Item", bundle: #bundle) }
	private var newTitle: Text { Text("New Item", bundle: #bundle) }
}
