// PROTOTYPE — Variant A: "Picker sheet"
//
// The straight mirror of #10, with the member-List picker as the one novel screen.
// Toolbar + opens the Combo editor (name, emoji, draw mode) exactly as a List's; saving
// lands you on the new Combo's detail, empty, prompting you to add Lists. Membership is a
// separate multi-select sheet reached by the detail's toolbar +, and a member comes off with
// a trailing swipe. Row caption is counts: "3 Lists · 13 items".

import SwiftUI

struct VariantACombineTab: View {
	@Bindable var store: Store
	@State private var editing: Combo?
	@State private var isCreating = false
	@State private var path: [Combo.ID] = []
	@State private var confirmingDelete: Combo?

	var body: some View {
		NavigationStack(path: $path) {
			Group {
				if store.combos.isEmpty {
					CombosEmptyState(hasLists: !store.lists.isEmpty) { isCreating = true }
				} else {
					List {
						ForEach(store.combos) { combo in
							NavigationLink(value: combo.id) {
								row(combo)
							}
							.swipeActions(edge: .leading) {
								Button("Edit", systemImage: "pencil") { editing = combo }.tint(.blue)
							}
							.swipeActions {
								Button("Delete", systemImage: "trash", role: .destructive) {
									// A Combo owns no Items — deleting one throws away an
									// arrangement, not content. Confirm only when it has members.
									if combo.listIDs.isEmpty {
										store.combos.removeAll { $0.id == combo.id }
									} else {
										confirmingDelete = combo
									}
								}
							}
						}
					}
					.refreshable {}
					.confirmationDialog(
						"Delete “\(confirmingDelete?.name ?? "")”?",
						isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
						titleVisibility: .visible,
						presenting: confirmingDelete
					) { combo in
						Button("Delete Combo", role: .destructive) {
							store.combos.removeAll { $0.id == combo.id }
						}
					} message: { _ in
						Text("The Lists in it are kept. This happens on your other devices too.")
					}
				}
			}
			.navigationTitle("Combine")
			.task { if LaunchArgs.opensDetail, let first = store.combos.first { path = [first.id] } }
			.navigationDestination(for: Combo.ID.self) { id in
				VariantAComboDetail(store: store, id: id)
			}
			.toolbar {
				Button("New Combo", systemImage: "plus") { isCreating = true }
					.disabled(store.lists.isEmpty)
			}
			.sheet(isPresented: $isCreating) {
				ComboEditor(combo: Combo(name: "")) { combo in
					store.combos.append(combo)
					// Straight into the detail, which is where you pick the Lists.
					path = [combo.id]
				}
			}
			.sheet(item: $editing) { combo in
				ComboEditor(combo: combo) { store[$0.id] = $0 }
			}
		}
	}

	private func row(_ combo: Combo) -> some View {
		HStack(spacing: 12) {
			Text(combo.emoji ?? "🎲")
				.font(.title2)
				.opacity(combo.emoji == nil ? 0.25 : 1)
			VStack(alignment: .leading, spacing: 2) {
				Text(combo.name)
				Text(store.countsCaption(for: combo)).font(.caption).foregroundStyle(.secondary)
			}
		}
	}
}

struct VariantAComboDetail: View {
	@Bindable var store: Store
	let id: Combo.ID
	@State private var isPicking = false
	@State private var isRandomising = false

	private var combo: Combo { store[id] }

	var body: some View {
		Group {
			if store.members(of: combo).isEmpty {
				ContentUnavailableView {
					Label("No Lists", systemImage: "square.stack.3d.up")
				} description: {
					Text("Pick the Lists to combine. Their items get pooled together.")
				} actions: {
					Button("Choose Lists") { isPicking = true }.buttonStyle(.borderedProminent)
				}
			} else {
				List {
					ForEach(store.members(of: combo)) { list in
						memberRow(list)
							.swipeActions {
								Button("Remove", systemImage: "minus.circle", role: .destructive) {
									store[id].listIDs.removeAll { $0 == list.id }
								}
							}
					}
				}
			}
		}
		.navigationTitle(combo.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Choose Lists", systemImage: "plus") { isPicking = true }
		}
		.safeAreaInset(edge: .bottom) {
			PinnedRandomiseBar(
				store: store,
				comboID: id,
				caption: store.countsCaption(for: combo),
				isRandomising: $isRandomising
			)
		}
		.sheet(isPresented: $isPicking) {
			ListPicker(store: store, selected: $store[id].listIDs)
		}
		.sheet(isPresented: $isRandomising) {
			ResultSheet(store: store, comboID: id)
		}
	}

	/// Inert: a member row is a statement of membership, not a way into the List. Tapping
	/// through to the Lists tab's detail would cross tabs and leave you unsure how to get back.
	private func memberRow(_ list: RandomList) -> some View {
		HStack(spacing: 12) {
			Text(list.emoji ?? "🎲").font(.title2).opacity(list.emoji == nil ? 0.25 : 1)
			VStack(alignment: .leading, spacing: 2) {
				Text(list.name)
				Text(list.poolCaption).font(.caption).foregroundStyle(.secondary)
			}
		}
	}
}

/// The one novel screen in this tab: a multi-select of every List.
struct ListPicker: View {
	let store: Store
	@Binding var selected: [RandomList.ID]
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List(store.lists) { list in
				Button {
					toggle(list.id)
				} label: {
					HStack(spacing: 12) {
						Text(list.emoji ?? "🎲").font(.title2).opacity(list.emoji == nil ? 0.25 : 1)
						VStack(alignment: .leading, spacing: 2) {
							Text(list.name).foregroundStyle(.primary)
							// Empty Lists are shown and are selectable — there is no minimum,
							// and a List you are about to fill is a reasonable thing to add.
							Text(list.poolCaption)
								.font(.caption)
								.foregroundStyle(list.items.isEmpty ? .tertiary : .secondary)
						}
						Spacer()
						if selected.contains(list.id) {
							Image(systemName: "checkmark").foregroundStyle(.tint)
						}
					}
				}
				.buttonStyle(.plain)
			}
			.navigationTitle("Choose Lists")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
			}
		}
		.presentationDetents([.large])
	}

	private func toggle(_ id: RandomList.ID) {
		if let index = selected.firstIndex(of: id) {
			selected.remove(at: index)
		} else {
			selected.append(id)
		}
	}
}

/// Name, emoji, draw mode — the same form a List gets in #10, and nothing about membership.
struct ComboEditor: View {
	@State var combo: Combo
	let onSave: (Combo) -> Void
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $combo.name)
					TextField("Emoji", text: Binding(
						get: { combo.emoji ?? "" },
						set: { combo.emoji = $0.last.map(String.init) }
					))
				}
				Section {
					Picker("Draw mode", selection: $combo.drawMode) {
						ForEach(DrawMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
					}
					.pickerStyle(.segmented)
				} footer: {
					Text(combo.drawMode == .deck
						? "Deals each pooled item once, then offers a reshuffle. Separate from each List's own deck."
						: "Picks at random from every item in every List. Repeats are possible.")
				}
			}
			.navigationTitle(combo.name.isEmpty ? "New Combo" : "Edit Combo")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") { onSave(combo); dismiss() }
						.disabled(combo.name.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
		}
		.presentationDetents([.medium])
	}
}
