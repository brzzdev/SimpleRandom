// PROTOTYPE — Variant C: "Cards & header"
//
// Randomise-forward. The index is cards, each with its own Randomise button, so the common
// case (open app, pick from Lunch) never opens the list at all. The detail screen leads with
// a header carrying the name, the mode and the primary button; items are just the contents below.

import SwiftUI

struct VariantCListsTab: View {
	@Bindable var store: Store
	@State private var editing: RandomList?
	@State private var randomising: RandomList?
	@State private var path: [RandomList.ID] = []

	var body: some View {
		NavigationStack(path: $path) {
			ScrollView {
				LazyVStack(spacing: 14) {
					ForEach(store.lists) { list in
						NavigationLink(value: list.id) { card(list) }
							.buttonStyle(.plain)
							.contextMenu {
								Button("Edit", systemImage: "pencil") { editing = list }
								Button("Delete", systemImage: "trash", role: .destructive) {
									store.lists.removeAll { $0.id == list.id }
								}
							}
					}

					Button {
						editing = RandomList(name: "")
					} label: {
						Label("New List", systemImage: "plus")
							.frame(maxWidth: .infinity)
							.padding(.vertical, 28)
							.background(
								RoundedRectangle(cornerRadius: 18)
									.strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
									.foregroundStyle(.tertiary)
							)
					}
					.padding(.top, store.lists.isEmpty ? 80 : 0)
				}
				.padding()
				.padding(.bottom, 60)
			}
			.background(Color(.systemGroupedBackground))
			.navigationTitle("Lists")
			.task { if LaunchArgs.opensDetail, let first = store.lists.first { path = [first.id] } }
			.refreshable {}
			.navigationDestination(for: RandomList.ID.self) { id in
				VariantCListDetail(store: store, id: id)
			}
			.overlay {
				if store.lists.isEmpty {
					Text("Nothing to pick from yet")
						.foregroundStyle(.secondary)
						.offset(y: -140)
						.allowsHitTesting(false)
				}
			}
			.sheet(item: $editing) { list in
				VariantAListEditor(list: list) { edited in
					if store.lists.contains(where: { $0.id == edited.id }) {
						store[edited.id] = edited
					} else {
						store.lists.append(edited)
					}
				}
			}
			.sheet(item: $randomising) { ResultSheetStub(list: $0) }
		}
	}

	private func card(_ list: RandomList) -> some View {
		HStack(spacing: 16) {
			Text(list.emoji ?? "🎲").font(.system(size: 40)).opacity(list.emoji == nil ? 0.2 : 1)
			VStack(alignment: .leading, spacing: 4) {
				Text(list.name).font(.headline)
				Text(list.subtitle).font(.caption).foregroundStyle(.secondary)
			}
			Spacer()
			Button {
				randomising = list
			} label: {
				Image(systemName: "dice.fill").font(.title3).padding(10)
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.circle)
			.disabled(list.items.isEmpty)
		}
		.padding(16)
		.background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
	}
}

struct VariantCListDetail: View {
	@Bindable var store: Store
	let id: RandomList.ID
	@State private var editingItem: Item?
	@State private var isRandomising = false

	private var list: RandomList { store[id] }

	var body: some View {
		List {
			Section {
				VStack(spacing: 14) {
					Text(list.emoji ?? "🎲").font(.system(size: 56))
					Picker("Draw mode", selection: Binding(get: { list.drawMode }, set: { store[id].drawMode = $0 })) {
						ForEach(DrawMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
					}
					.pickerStyle(.segmented)
					Button {
						isRandomising = true
					} label: {
						Label(list.isExhausted ? "Reshuffle" : "Randomise", systemImage: "dice")
							.font(.headline)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 6)
					}
					.buttonStyle(.borderedProminent)
					.disabled(list.items.isEmpty)
					Text(list.items.isEmpty ? "Add an item below to randomise" : list.subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
				.listRowBackground(Color.clear)
			}

			Section("Items") {
				ForEach(list.items) { item in
					Button {
						editingItem = item
					} label: {
						HStack {
							Text(item.title).foregroundStyle(item.isDealt ? .secondary : .primary)
							Spacer()
							if item.isDealt { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tertiary) }
						}
					}
					.buttonStyle(.plain)
					.swipeActions {
						Button("Delete", systemImage: "trash", role: .destructive) {
							store[id].items.removeAll { $0.id == item.id }
						}
					}
				}

				Button {
					editingItem = Item(title: "")
				} label: {
					Label("Add item", systemImage: "plus")
				}
			}
		}
		.navigationTitle(list.name)
		.navigationBarTitleDisplayMode(.inline)
		.sheet(item: $editingItem) { item in
			VariantAItemEditor(item: item) { edited in
				if let index = store[id].items.firstIndex(where: { $0.id == edited.id }) {
					store[id].items[index] = edited
				} else {
					store[id].items.append(edited)
				}
			}
		}
		.sheet(isPresented: $isRandomising) { ResultSheetStub(list: list) }
	}
}
