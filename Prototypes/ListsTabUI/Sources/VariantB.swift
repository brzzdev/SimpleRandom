// PROTOTYPE — Variant B: "Inline & FAB"
//
// No editor sheets anywhere. Creating and renaming happen in place, in the row, with the
// keyboard staying up so you can add five things in five seconds (Reminders / Notes checklist).
// Randomise is a circular floating button over the scroll that gets out of the way of the keyboard.

import SwiftUI

struct VariantBListsTab: View {
	@Bindable var store: Store
	@State private var draftName = ""
	@State private var renaming: RandomList.ID?
	@FocusState private var focus: Focus?
	@State private var path: [RandomList.ID] = []

	private enum Focus: Hashable { case draft, rename(RandomList.ID) }

	var body: some View {
		NavigationStack(path: $path) {
			List {
				ForEach(store.lists) { list in
					if renaming == list.id {
						TextField("Name", text: Binding(get: { store[list.id].name }, set: { store[list.id].name = $0 }))
							.focused($focus, equals: .rename(list.id))
							.onSubmit { renaming = nil }
					} else {
						NavigationLink(value: list.id) { row(list) }
							.contextMenu {
								Button("Rename", systemImage: "pencil") {
									renaming = list.id
									focus = .rename(list.id)
								}
								Button("Toggle Deck", systemImage: "rectangle.stack") {
									store[list.id].drawMode = list.drawMode == .deck ? .independent : .deck
								}
								Button("Delete", systemImage: "trash", role: .destructive) {
									store.lists.removeAll { $0.id == list.id }
								}
							}
							.swipeActions {
								Button("Delete", systemImage: "trash", role: .destructive) {
									store.lists.removeAll { $0.id == list.id }
								}
							}
					}
				}

				HStack(spacing: 12) {
					Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
					TextField(store.lists.isEmpty ? "Name your first list" : "New List", text: $draftName)
						.focused($focus, equals: .draft)
						.onSubmit(commitDraft)
						.submitLabel(.next)
				}
			}
			.navigationTitle("Lists")
			.task { if LaunchArgs.opensDetail, let first = store.lists.first { path = [first.id] } }
			.navigationDestination(for: RandomList.ID.self) { id in
				VariantBListDetail(store: store, id: id)
			}
			.refreshable {}
			.overlay {
				if store.lists.isEmpty {
					Text("Lists live here.\nStart typing below.")
						.multilineTextAlignment(.center)
						.foregroundStyle(.secondary)
						.allowsHitTesting(false)
						.offset(y: -60)
				}
			}
		}
	}

	private func row(_ list: RandomList) -> some View {
		HStack(spacing: 14) {
			ZStack {
				RoundedRectangle(cornerRadius: 10).fill(.quaternary).frame(width: 38, height: 38)
				Text(list.emoji ?? String(list.name.prefix(1))).font(.title3)
			}
			VStack(alignment: .leading, spacing: 1) {
				Text(list.name)
				Text(list.subtitle).font(.caption2).foregroundStyle(.secondary)
			}
		}
	}

	private func commitDraft() {
		let name = draftName.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty else { return }
		store.lists.append(RandomList(name: name))
		draftName = ""
		focus = .draft
	}
}

struct VariantBListDetail: View {
	@Bindable var store: Store
	let id: RandomList.ID
	@State private var draft = ""
	@State private var isRandomising = false
	@FocusState private var isAdding: Bool

	private var list: RandomList { store[id] }

	var body: some View {
		List {
			ForEach(list.items) { item in
				TextField("Item", text: Binding(
					get: { store[id].items.first { $0.id == item.id }?.title ?? "" },
					set: { text in
						guard let index = store[id].items.firstIndex(where: { $0.id == item.id }) else { return }
						store[id].items[index].title = text
					}
				))
				.foregroundStyle(item.isDealt ? .secondary : .primary)
				.swipeActions {
					Button("Delete", systemImage: "trash", role: .destructive) {
						store[id].items.removeAll { $0.id == item.id }
					}
				}
			}

			HStack(spacing: 12) {
				Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
				TextField(list.items.isEmpty ? "Add the first thing" : "Add item", text: $draft)
					.focused($isAdding)
					.submitLabel(.next)
					.onSubmit {
						let title = draft.trimmingCharacters(in: .whitespaces)
						guard !title.isEmpty else { return }
						store[id].items.append(Item(title: title))
						draft = ""
						isAdding = true
					}
			}
		}
		.navigationTitle(list.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				VStack(spacing: 0) {
					Text(list.name).font(.headline)
					Text(list.subtitle).font(.caption2).foregroundStyle(.secondary)
				}
			}
		}
		.overlay(alignment: .bottomTrailing) {
			if !isAdding {
				Button {
					isRandomising = true
				} label: {
					Image(systemName: "dice.fill")
						.font(.title2)
						.frame(width: 60, height: 60)
				}
				.buttonStyle(.borderedProminent)
				.buttonBorderShape(.circle)
				.disabled(list.items.isEmpty)
				.padding(.trailing, 20)
				.padding(.bottom, 20)
				.shadow(radius: 8, y: 4)
				.transition(.scale)
			}
		}
		.animation(.snappy, value: isAdding)
		.sheet(isPresented: $isRandomising) { ResultSheetStub(list: list) }
	}
}
