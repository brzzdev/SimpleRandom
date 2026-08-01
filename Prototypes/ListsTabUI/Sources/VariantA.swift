// PROTOTYPE — Variant A: "Sheets & pinned bar"
//
// The conventional answer. Everything is a system control in its expected place:
// toolbar + to create, an editor sheet for name/emoji/mode, swipe to rename or delete,
// and a full-width Randomise button pinned in the bottom safe area so it never covers a row.

import SwiftUI

struct VariantAListsTab: View {
	@Bindable var store: Store
	@State private var editing: RandomList?
	@State private var isCreating = false
	@State private var path: [RandomList.ID] = []

	var body: some View {
		NavigationStack(path: $path) {
			Group {
				if store.lists.isEmpty {
					ContentUnavailableView {
						Label("No Lists", systemImage: "list.bullet.rectangle")
					} description: {
						Text("Make a list of things to pick between — lunch spots, films, chores.")
					} actions: {
						Button("New List") { isCreating = true }.buttonStyle(.borderedProminent)
					}
				} else {
					List {
						ForEach(store.lists) { list in
							NavigationLink(value: list.id) {
								row(list)
							}
							.swipeActions(edge: .leading) {
								Button("Edit", systemImage: "pencil") { editing = list }.tint(.blue)
							}
							.swipeActions {
								Button("Delete", systemImage: "trash", role: .destructive) {
									store.lists.removeAll { $0.id == list.id }
								}
							}
						}
					}
					.refreshable {}
				}
			}
			.navigationTitle("Lists")
			.task { if LaunchArgs.opensDetail, let first = store.lists.first { path = [first.id] } }
			.navigationDestination(for: RandomList.ID.self) { id in
				VariantAListDetail(store: store, id: id)
			}
			.toolbar {
				Button("New List", systemImage: "plus") { isCreating = true }
			}
			.sheet(isPresented: $isCreating) {
				VariantAListEditor(list: RandomList(name: "")) { store.lists.append($0) }
			}
			.sheet(item: $editing) { list in
				VariantAListEditor(list: list) { store[$0.id] = $0 }
			}
		}
	}

	private func row(_ list: RandomList) -> some View {
		HStack(spacing: 12) {
			Text(list.emoji ?? "🎲")
				.font(.title2)
				.opacity(list.emoji == nil ? 0.25 : 1)
			VStack(alignment: .leading, spacing: 2) {
				Text(list.name)
				Text(list.subtitle).font(.caption).foregroundStyle(.secondary)
			}
		}
	}
}

struct VariantAListDetail: View {
	@Bindable var store: Store
	let id: RandomList.ID
	@State private var editingItem: Item?
	@State private var isAdding = false
	@State private var isRandomising = false

	private var list: RandomList { store[id] }

	var body: some View {
		Group {
			if list.items.isEmpty {
				ContentUnavailableView(
					"No Items",
					systemImage: "text.badge.plus",
					description: Text("Add the things you want to pick between.")
				)
			} else {
				List {
					ForEach(list.items) { item in
						Button {
							editingItem = item
						} label: {
							HStack {
								Text(item.title).foregroundStyle(item.isDealt ? .secondary : .primary)
								Spacer()
								if item.isDealt {
									Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
								}
							}
						}
						.buttonStyle(.plain)
						.swipeActions {
							Button("Delete", systemImage: "trash", role: .destructive) {
								store[id].items.removeAll { $0.id == item.id }
							}
						}
					}
				}
			}
		}
		.navigationTitle(list.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Add Item", systemImage: "plus") { isAdding = true }
		}
		.safeAreaInset(edge: .bottom) {
			VStack(spacing: 6) {
				Button {
					isRandomising = true
				} label: {
					Label(list.isExhausted ? "Reshuffle" : "Randomise", systemImage: "dice")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(list.items.isEmpty)

				Text(list.items.isEmpty ? "Add an item to randomise" : list.subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal)
			.padding(.vertical, 8)
			.background(.bar)
		}
		.sheet(isPresented: $isAdding) {
			VariantAItemEditor(item: Item(title: "")) { store[id].items.append($0) }
		}
		.sheet(item: $editingItem) { item in
			VariantAItemEditor(item: item) { edited in
				guard let index = store[id].items.firstIndex(where: { $0.id == edited.id }) else { return }
				store[id].items[index] = edited
			}
		}
		.sheet(isPresented: $isRandomising) { ResultSheetStub(list: list) }
	}
}

struct VariantAListEditor: View {
	@State var list: RandomList
	let onSave: (RandomList) -> Void
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $list.name)
					TextField("Emoji", text: Binding(get: { list.emoji ?? "" }, set: { list.emoji = $0.isEmpty ? nil : $0 }))
				}
				Section {
					Picker("Draw mode", selection: $list.drawMode) {
						ForEach(DrawMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
					}
					.pickerStyle(.segmented)
				} footer: {
					Text(list.drawMode == .deck
						? "Deals each item once, then offers a reshuffle."
						: "Picks at random every time. Repeats are possible.")
				}
			}
			.navigationTitle(list.name.isEmpty ? "New List" : "Edit List")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") { onSave(list); dismiss() }
						.disabled(list.name.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
		}
		.presentationDetents([.medium])
	}
}

struct VariantAItemEditor: View {
	@State var item: Item
	let onSave: (Item) -> Void
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			Form {
				TextField("Item", text: $item.title)
			}
			.navigationTitle(item.title.isEmpty ? "New Item" : "Edit Item")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") { onSave(item); dismiss() }
						.disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
		}
		.presentationDetents([.height(180)])
	}
}
