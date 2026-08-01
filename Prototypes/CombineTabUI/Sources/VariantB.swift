// PROTOTYPE — Variant B: "One sheet" — THE CHOSEN VARIANT, with issue #13's answers folded in.
//
// A Combo is *defined* in a single form: name, emoji, draw mode, and a Lists section listing
// every List with a checkmark. Creating and editing are the same sheet, so there is exactly
// one place a Combo's membership is changed, and nothing exists until Save — a half-made Combo
// never reaches the tab or anyone else's iPhone.
//
// Folded in after the prototype was judged:
//   - Row caption is **counts** — "3 Lists · 12 items", "3 Lists · Deck · 10 of 13 left" —
//     mirroring the Lists tab and the only option that shows a Deck running down from the index.
//   - A member row **pushes the real List detail**, the same screen the Lists tab pushes,
//     Randomise bar and all. See SharedListDetail.
//   - Deleting a Combo confirms only when it has members.

import SwiftUI

/// Combine goes two deep now: Combo detail, then a member's List detail.
enum Route: Hashable {
	case combo(Combo.ID)
	case list(RandomList.ID)
}

struct VariantBCombineTab: View {
	@Bindable var store: Store
	@State private var editing: Combo?
	@State private var isCreating = false
	@State private var path: [Route] = []
	@State private var confirmingDelete: Combo?

	var body: some View {
		NavigationStack(path: $path) {
			Group {
				if store.combos.isEmpty {
					CombosEmptyState(hasLists: !store.lists.isEmpty) { isCreating = true }
				} else {
					List {
						ForEach(store.combos) { combo in
							NavigationLink(value: Route.combo(combo.id)) {
								row(combo)
							}
							.swipeActions(edge: .leading) {
								Button("Edit", systemImage: "pencil") { editing = combo }.tint(.blue)
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
			.task { if LaunchArgs.opensDetail, let first = store.combos.first { path = [.combo(first.id)] } }
			.navigationDestination(for: Route.self) { route in
				switch route {
				case .combo(let id): VariantBComboDetail(store: store, id: id)
				case .list(let id): SharedListDetail(store: store, id: id)
				}
			}
			.toolbar {
				Button("New Combo", systemImage: "plus") { isCreating = true }
					.disabled(store.lists.isEmpty)
			}
			.sheet(isPresented: $isCreating) {
				// Nothing is created until Save, so a half-made Combo never reaches the tab —
				// or, under sync, anyone else's iPhone.
				ComboFormSheet(store: store, combo: Combo(name: "")) { store.combos.append($0) }
			}
			.sheet(item: $editing) { combo in
				ComboFormSheet(store: store, combo: combo) { store[$0.id] = $0 }
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
				Text(store.countsCaption(for: combo))
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
	}
}

struct VariantBComboDetail: View {
	@Bindable var store: Store
	let id: Combo.ID
	@State private var isEditing = false
	@State private var isRandomising = false

	private var combo: Combo { store[id] }

	var body: some View {
		Group {
			if store.members(of: combo).isEmpty {
				ContentUnavailableView {
					Label("No Lists", systemImage: "square.stack.3d.up")
				} description: {
					Text("Edit this Combo to pick the Lists it draws from.")
				} actions: {
					Button("Edit Combo") { isEditing = true }.buttonStyle(.borderedProminent)
				}
			} else {
				List {
					Section {
						ForEach(store.members(of: combo)) { list in
							// Pushes the *same* List detail the Lists tab pushes — which is why
							// it is extracted into its own target both features depend on.
							NavigationLink(value: Route.list(list.id)) {
								HStack(spacing: 12) {
									Text(list.emoji ?? "🎲").font(.title2).opacity(list.emoji == nil ? 0.25 : 1)
									VStack(alignment: .leading, spacing: 2) {
										Text(list.name)
										Text(list.poolCaption).font(.caption).foregroundStyle(.secondary)
									}
								}
							}
						}
					} header: {
						Text("Drawing from")
					} footer: {
						// No swipe-to-remove: membership has exactly one home, the edit sheet.
						Text("Change which Lists are in this Combo with Edit.")
					}
				}
			}
		}
		.navigationTitle(combo.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Edit") { isEditing = true }
		}
		.safeAreaInset(edge: .bottom) {
			PinnedRandomiseBar(
				store: store,
				comboID: id,
				caption: store.countsCaption(for: combo),
				isRandomising: $isRandomising
			)
		}
		.sheet(isPresented: $isEditing) {
			ComboFormSheet(store: store, combo: combo) { store[$0.id] = $0 }
		}
		.sheet(isPresented: $isRandomising) {
			ResultSheet(store: store, comboID: id)
		}
	}
}

/// Everything about a Combo in one form — identity, draw mode, and membership.
struct ComboFormSheet: View {
	let store: Store
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
				Section {
					ForEach(store.lists) { list in
						Button {
							toggle(list.id)
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
								if combo.listIDs.contains(list.id) {
									Image(systemName: "checkmark").foregroundStyle(.tint)
								}
							}
						}
						.buttonStyle(.plain)
					}
				} header: {
					Text("Lists")
				} footer: {
					Text(pooledFooter)
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
	}

	/// Live feedback on what the pool will be, since the whole point is the total.
	private var pooledFooter: String {
		let count = combo.listIDs.compactMap(store.list).flatMap(\.items).count
		guard !combo.listIDs.isEmpty else { return "Pick the Lists to draw from." }
		return count == 1 ? "1 item in the pool." : "\(count) items in the pool."
	}

	private func toggle(_ id: RandomList.ID) {
		if let index = combo.listIDs.firstIndex(of: id) {
			combo.listIDs.remove(at: index)
		} else {
			combo.listIDs.append(id)
		}
	}
}
