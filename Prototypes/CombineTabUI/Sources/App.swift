// PROTOTYPE — throwaway. Answers https://github.com/brzzdev/SimpleRandom/issues/13
//
// Three takes on the Combine tab + Combo detail, switchable from the dark strip at the top
// (‹ ›). That strip is prototype chrome, not app design.
//
// Issue #10 already settled that Combine *mirrors* the Lists tab — same rows, same editor
// sheet, same pinned Randomise button — so the variants do not re-litigate that. They differ
// on the one genuinely open thing: **where membership is chosen and edited.**
//
//   A — Picker sheet      create, then add member Lists from a multi-select sheet; swipe to remove
//   B — One sheet         name, emoji, mode and the member Lists are all one form; detail is read-only
//   C — Detail is picker   the detail lists *every* List; tapping toggles membership
//
// "Sample / No Combos / No Lists" swaps the store so the empty states are one tap away.

import SwiftUI

enum Variant: String, CaseIterable {
	case a = "A", b = "B", c = "C"

	var name: String {
		switch self {
		case .a: "Picker sheet"
		case .b: "One sheet"
		case .c: "Detail is picker"
		}
	}
}

enum Fixture: String, CaseIterable {
	case sample = "Sample", noCombos = "No Combos", noLists = "No Lists"

	@MainActor func store() -> Store {
		switch self {
		case .sample: .sample()
		case .noCombos: .empty()
		case .noLists: .noLists()
		}
	}
}

/// Launch args, so screenshots can be taken without tapping: `--variant B --detail`.
enum LaunchArgs {
	static let arguments = ProcessInfo.processInfo.arguments
	static var variant: Variant {
		guard let index = arguments.firstIndex(of: "--variant"), index + 1 < arguments.count else { return .a }
		return Variant(rawValue: arguments[index + 1]) ?? .a
	}
	static var opensDetail: Bool { arguments.contains("--detail") }
}

@main
struct PrototypeApp: App {
	var body: some Scene {
		WindowGroup {
			PrototypeRoot()
		}
	}
}

struct PrototypeRoot: View {
	@State private var variant = LaunchArgs.variant
	@State private var fixture = Fixture.sample
	@State private var store = Store.sample()
	@State private var tab = 1

	var body: some View {
		VStack(spacing: 0) {
			switcher
			// Opens on Combine — the app opens on Lists, but this prototype is about this tab.
			TabView(selection: $tab) {
				Tab("Lists", systemImage: "list.bullet", value: 0) {
					ListsTabStub(store: store)
				}
				Tab("Combine", systemImage: "square.stack.3d.up", value: 1) {
					switch variant {
					case .a: VariantACombineTab(store: store)
					case .b: VariantBCombineTab(store: store)
					case .c: VariantCCombineTab(store: store)
					}
				}
				Tab("Settings", systemImage: "gear", value: 2) {
					NavigationStack { Text("Settings").navigationTitle("Settings") }
				}
			}
			.id(variant)
		}
	}

	private var switcher: some View {
		HStack(spacing: 12) {
			Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
			Text("\(variant.rawValue) — \(variant.name)")
				.font(.footnote.weight(.semibold))
				.frame(maxWidth: .infinity)
			Button { cycle(1) } label: { Image(systemName: "chevron.right") }
			Menu(fixture.rawValue) {
				ForEach(Fixture.allCases, id: \.self) { option in
					Button(option.rawValue) {
						fixture = option
						store = option.store()
					}
				}
			}
			.font(.caption.weight(.semibold))
			.buttonStyle(.bordered)
			.tint(.white)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.foregroundStyle(.white)
		.background(.black)
	}

	private func cycle(_ step: Int) {
		let all = Variant.allCases
		let index = (all.firstIndex(of: variant)! + step + all.count) % all.count
		variant = all[index]
	}
}

// MARK: - Combo vocabulary

/// Why the Combine tab can be disabled, and what the pinned button's caption says about it.
/// Three distinct reasons, deliberately distinguished — "nothing to draw" is not one message.
enum ComboReadiness: Equatable {
	case noMembers
	case emptyPool
	case exhausted
	case ready

	var prompt: String {
		switch self {
		case .noMembers: "Add a List to randomise"
		case .emptyPool: "The Lists in this Combo have no items"
		case .exhausted: "Every item has been dealt"
		case .ready: ""
		}
	}

	var isDisabled: Bool { self == .noMembers || self == .emptyPool }
}

extension Store {
	func readiness(of combo: Combo) -> ComboReadiness {
		if members(of: combo).isEmpty { return .noMembers }
		let pool = pool(of: combo)
		if pool.isEmpty { return .emptyPool }
		if combo.drawMode == .deck, pool.allSatisfy({ combo.dealtItemIDs.contains($0.item.id) }) { return .exhausted }
		return .ready
	}

	/// The chosen row caption: counts, mirroring the Lists tab and showing a Deck running down.
	func countsCaption(for combo: Combo) -> String {
		let lists = members(of: combo).count
		let pool = pool(of: combo)
		let listPart = lists == 1 ? "1 List" : "\(lists) Lists"
		switch (combo.drawMode, lists, pool.count) {
		case (_, 0, _): return "No Lists"
		case (_, _, 0): return "\(listPart) · no items"
		case (.independent, _, let count): return "\(listPart) · \(count) items"
		case (.deck, _, let count):
			let left = count - pool.filter { combo.dealtItemIDs.contains($0.item.id) }.count
			return "\(listPart) · Deck · \(left) of \(count) left"
		}
	}

	/// The rejected row caption: the member names. Kept as the record of what was on offer —
	/// it reads well but drops the pool size and a Deck's progress, which counts keep.
	func namesCaption(for combo: Combo) -> String {
		let names = members(of: combo).map(\.name)
		guard !names.isEmpty else { return "No Lists" }
		return names.joined(separator: " · ")
	}

	/// Variant C's row caption: the member emoji as a strip, plus the pooled size.
	func emojiCaption(for combo: Combo) -> String {
		let members = members(of: combo)
		guard !members.isEmpty else { return "No Lists" }
		let strip = members.map { $0.emoji ?? "•" }.joined()
		let pool = pool(of: combo)
		switch (combo.drawMode, pool.count) {
		case (_, 0): return "\(strip)  no items"
		case (.independent, let count): return "\(strip)  \(count) items"
		case (.deck, let count):
			let left = count - pool.filter { combo.dealtItemIDs.contains($0.item.id) }.count
			return "\(strip)  Deck · \(left) of \(count) left"
		}
	}
}

extension RandomList {
	/// A member List's caption **never** shows its own deck state: a Combo pools every Item
	/// regardless, so `Deck · 2 of 5 left` here would promise something false. Counts only.
	var poolCaption: String {
		switch items.count {
		case 0: "No items"
		case 1: "1 item"
		case let count: "\(count) items"
		}
	}
}

// MARK: - Shared bits

/// The Combine path's result sheet, as settled by issue #11 — centre stage, fixed medium
/// detent, with the one extra secondary line naming the source List.
struct ResultSheet: View {
	let store: Store
	let comboID: Combo.ID
	@State private var drawn: (list: RandomList, item: Item)?
	@Environment(\.dismiss) private var dismiss

	private var combo: Combo { store[comboID] }

	var body: some View {
		VStack(spacing: 16) {
			Spacer()
			if let drawn {
				Text(drawn.item.title)
					.font(.largeTitle.bold())
					.multilineTextAlignment(.center)
					.minimumScaleFactor(0.5)
				Text("\(drawn.list.emoji ?? "") \(drawn.list.name)")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				Text("That's the whole deck")
					.font(.largeTitle.bold())
					.multilineTextAlignment(.center)
			}
			Spacer()
			Button(drawn == nil ? "Reshuffle" : "Again") {
				if drawn == nil {
					store[comboID].dealtItemIDs = []
				}
				draw()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		}
		.padding(24)
		.presentationDetents([.medium])
		.onAppear { draw() }
	}

	private func draw() {
		let pool = store.pool(of: combo)
		let candidates = combo.drawMode == .deck
			? pool.filter { !combo.dealtItemIDs.contains($0.item.id) }
			: pool
		guard let pick = candidates.randomElement() else {
			drawn = nil
			return
		}
		if combo.drawMode == .deck {
			store[comboID].dealtItemIDs.insert(pick.item.id)
		}
		drawn = pick
	}
}

/// The Lists path's result sheet — issue #11's variant A with *nothing* around the Item.
struct ListResultSheet: View {
	@Bindable var store: Store
	let listID: RandomList.ID
	@State private var drawn: Item?
	@State private var isExhausted = false

	private var list: RandomList { store.list(listID) ?? RandomList(name: "?") }

	var body: some View {
		VStack(spacing: 16) {
			Spacer()
			Text(isExhausted ? "That's the whole deck" : (drawn?.title ?? "—"))
				.font(.largeTitle.bold())
				.multilineTextAlignment(.center)
				.minimumScaleFactor(0.5)
			Spacer()
			Button(isExhausted ? "Reshuffle" : "Again") {
				if isExhausted { reshuffle() }
				draw()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		}
		.padding(24)
		.presentationDetents([.medium])
		.onAppear { draw() }
	}

	private func draw() {
		let candidates = list.drawMode == .deck ? list.items.filter { !$0.isDealt } : list.items
		guard let pick = candidates.randomElement() else {
			isExhausted = true
			return
		}
		isExhausted = false
		drawn = pick
		guard list.drawMode == .deck, let index = store.lists.firstIndex(where: { $0.id == listID }) else { return }
		store.lists[index].items.firstIndex { $0.id == pick.id }.map {
			store.lists[index].items[$0].isDealt = true
		}
	}

	private func reshuffle() {
		guard let index = store.lists.firstIndex(where: { $0.id == listID }) else { return }
		for item in store.lists[index].items.indices {
			store.lists[index].items[item].isDealt = false
		}
	}
}

/// Issue #10's List detail. Not up for decision here — it is in the prototype because #13
/// decided a Combo's member row pushes **this** screen, unchanged, Randomise bar and all.
/// That is what forces it out of `ListsFeature` into a target both tabs depend on.
struct SharedListDetail: View {
	@Bindable var store: Store
	let id: RandomList.ID
	@State private var isRandomising = false

	private var list: RandomList { store.list(id) ?? RandomList(name: "?") }
	private var isExhausted: Bool {
		list.drawMode == .deck && !list.items.isEmpty && list.items.allSatisfy(\.isDealt)
	}

	var body: some View {
		Group {
			if list.items.isEmpty {
				ContentUnavailableView(
					"No Items",
					systemImage: "text.badge.plus",
					description: Text("Add the things you want to pick between.")
				)
			} else {
				List(list.items) { item in
					HStack {
						Text(item.title).foregroundStyle(item.isDealt ? .secondary : .primary)
						Spacer()
						if item.isDealt {
							Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
						}
					}
				}
			}
		}
		.navigationTitle(list.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Add Item", systemImage: "plus") {}
		}
		.safeAreaInset(edge: .bottom) {
			// Identical whether it was pushed from Lists or from inside a Combo. The deck it
			// runs is this List's own, which is what "decks are independent per surface" means.
			VStack(spacing: 6) {
				Button {
					isRandomising = true
				} label: {
					Label(isExhausted ? "Reshuffle" : "Randomise", systemImage: "dice")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(list.items.isEmpty)

				Text(list.items.isEmpty ? "Add an item to randomise" : listCaption)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal)
			.padding(.vertical, 8)
			.background(.bar)
		}
		.sheet(isPresented: $isRandomising) {
			ListResultSheet(store: store, listID: id)
		}
	}

	private var listCaption: String {
		guard list.drawMode == .deck else { return list.poolCaption }
		let left = list.items.count - list.items.filter(\.isDealt).count
		return "Deck · \(left) of \(list.items.count) left"
	}
}

/// Not the subject of this ticket — issue #10 settled the Lists tab. Here only so the real
/// tab bar is in the picture, the sample Lists are visible while judging a Combo, and the
/// pushed List detail can be seen to be the *same* screen from both tabs.
struct ListsTabStub: View {
	@Bindable var store: Store

	var body: some View {
		NavigationStack {
			List(store.lists) { list in
				NavigationLink(value: list.id) {
					HStack(spacing: 12) {
						Text(list.emoji ?? "🎲").font(.title2).opacity(list.emoji == nil ? 0.25 : 1)
						VStack(alignment: .leading, spacing: 2) {
							Text(list.name)
							Text(list.poolCaption).font(.caption).foregroundStyle(.secondary)
						}
					}
				}
			}
			.navigationTitle("Lists")
			.navigationDestination(for: RandomList.ID.self) { id in
				SharedListDetail(store: store, id: id)
			}
		}
	}
}

/// Shared by all three variants: the pinned bottom bar from #10, reading a Combo's readiness.
struct PinnedRandomiseBar: View {
	let store: Store
	let comboID: Combo.ID
	let caption: String
	@Binding var isRandomising: Bool

	var body: some View {
		let readiness = store.readiness(of: store[comboID])
		VStack(spacing: 6) {
			Button {
				if readiness == .exhausted {
					store[comboID].dealtItemIDs = []
				} else {
					isRandomising = true
				}
			} label: {
				Label(readiness == .exhausted ? "Reshuffle" : "Randomise", systemImage: "dice")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.disabled(readiness.isDisabled)

			Text(readiness == .ready ? caption : readiness.prompt)
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
		.background(.bar)
	}
}

/// Shared by all three variants: no Combos yet, but Lists exist — versus nothing at all.
struct CombosEmptyState: View {
	let hasLists: Bool
	let onCreate: () -> Void

	var body: some View {
		if hasLists {
			ContentUnavailableView {
				Label("No Combos", systemImage: "square.stack.3d.up")
			} description: {
				Text("Combine a few Lists and pick from all of them at once.")
			} actions: {
				Button("New Combo", action: onCreate).buttonStyle(.borderedProminent)
			}
		} else {
			ContentUnavailableView(
				"No Lists to Combine",
				systemImage: "square.stack.3d.up.slash",
				description: Text("Make a couple of Lists first, then combine them here.")
			)
		}
	}
}
