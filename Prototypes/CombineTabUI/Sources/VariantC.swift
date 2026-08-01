// PROTOTYPE — Variant C: "Detail is picker"
//
// There is no picker sheet and no membership form. The Combo detail *is* the picker: it shows
// every List in the app, members in a top section and everything else under "Other Lists",
// and tapping a row moves it between the two. Creating a Combo makes it immediately with a
// default name and pushes straight in, so the flow is: +, tap the Lists you want, randomise.
// Name, emoji and draw mode live behind a small header sheet, out of the way.
// Row caption is a strip of the member emoji plus the pool size: "🥪🍝🥡  13 items".

import SwiftUI

struct VariantCCombineTab: View {
	@Bindable var store: Store
	@State private var path: [Combo.ID] = []
	@State private var confirmingDelete: Combo?

	var body: some View {
		NavigationStack(path: $path) {
			Group {
				if store.combos.isEmpty {
					CombosEmptyState(hasLists: !store.lists.isEmpty) { create() }
				} else {
					List {
						ForEach(store.combos) { combo in
							NavigationLink(value: combo.id) {
								row(combo)
							}
							.swipeActions {
								Button("Delete", systemImage: "trash", role: .destructive) {
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
				VariantCComboDetail(store: store, id: id)
			}
			.toolbar {
				Button("New Combo", systemImage: "plus") { create() }
					.disabled(store.lists.isEmpty)
			}
		}
	}

	/// No naming step. The Combo exists the moment you tap + — which also means a half-made
	/// one syncs to your other iPhones, named "New Combo", until you rename it.
	private func create() {
		let combo = Combo(name: "New Combo")
		store.combos.append(combo)
		path = [combo.id]
	}

	private func row(_ combo: Combo) -> some View {
		HStack(spacing: 12) {
			Text(combo.emoji ?? "🎲")
				.font(.title2)
				.opacity(combo.emoji == nil ? 0.25 : 1)
			VStack(alignment: .leading, spacing: 2) {
				Text(combo.name)
				Text(store.emojiCaption(for: combo))
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
	}
}

struct VariantCComboDetail: View {
	@Bindable var store: Store
	let id: Combo.ID
	@State private var isEditingIdentity = false
	@State private var isRandomising = false

	private var combo: Combo { store[id] }
	private var members: [RandomList] { store.members(of: combo) }
	private var others: [RandomList] { store.lists.filter { !combo.listIDs.contains($0.id) } }

	var body: some View {
		List {
			if !members.isEmpty {
				Section("Drawing from") {
					ForEach(members) { list in
						pickerRow(list, isMember: true)
					}
				}
			}
			Section {
				ForEach(others) { list in
					pickerRow(list, isMember: false)
				}
			} header: {
				Text(members.isEmpty ? "Tap the Lists to combine" : "Other Lists")
			} footer: {
				if others.isEmpty, !members.isEmpty {
					Text("Every List is in this Combo.")
				}
			}
		}
		.navigationTitle(combo.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Edit", systemImage: "pencil") { isEditingIdentity = true }
		}
		.safeAreaInset(edge: .bottom) {
			PinnedRandomiseBar(
				store: store,
				comboID: id,
				caption: store.countsCaption(for: combo),
				isRandomising: $isRandomising
			)
		}
		.sheet(isPresented: $isEditingIdentity) {
			ComboIdentitySheet(combo: combo) { store[$0.id] = $0 }
		}
		.sheet(isPresented: $isRandomising) {
			ResultSheet(store: store, comboID: id)
		}
	}

	/// One row type for both sections — the only difference is the checkmark, so the gesture
	/// that adds a List is the same gesture that removes it.
	private func pickerRow(_ list: RandomList, isMember: Bool) -> some View {
		Button {
			if isMember {
				store[id].listIDs.removeAll { $0 == list.id }
			} else {
				store[id].listIDs.append(list.id)
			}
		} label: {
			HStack(spacing: 12) {
				Text(list.emoji ?? "🎲").font(.title2).opacity(list.emoji == nil ? 0.25 : 1)
				VStack(alignment: .leading, spacing: 2) {
					Text(list.name).foregroundStyle(.primary)
					Text(list.poolCaption)
						.font(.caption)
						.foregroundStyle(list.items.isEmpty ? .tertiary : .secondary)
				}
				Spacer()
				if isMember {
					Image(systemName: "checkmark").foregroundStyle(.tint)
				}
			}
		}
		.buttonStyle(.plain)
	}
}

/// Just the identity bits — the membership is the screen behind this.
struct ComboIdentitySheet: View {
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
			.navigationTitle("Edit Combo")
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
