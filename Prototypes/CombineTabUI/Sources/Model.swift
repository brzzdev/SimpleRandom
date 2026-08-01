// PROTOTYPE — throwaway. Answers https://github.com/brzzdev/SimpleRandom/issues/13
// In-memory only. No SQLiteData, no TCA, no persistence: this is about what it looks like.

import SwiftUI

struct Item: Identifiable, Hashable {
	let id = UUID()
	var title: String
	var isDealt = false
}

enum DrawMode: String, CaseIterable, Hashable {
	case independent = "Plain"
	case deck = "Deck"
}

struct RandomList: Identifiable, Hashable {
	let id = UUID()
	var name: String
	var emoji: String?
	var drawMode: DrawMode = .independent
	var items: [Item] = []
}

/// A saved set of Lists, referenced by id so it stays live as those Lists change.
struct Combo: Identifiable, Hashable {
	let id = UUID()
	var name: String
	var emoji: String?
	var drawMode: DrawMode = .independent
	var listIDs: [RandomList.ID] = []
	/// Stands in for `ComboDraw` rows — the Items this Combo has dealt. Deliberately
	/// separate from `Item.isDealt`, which is the *List's* deck and untouched by a Combo.
	var dealtItemIDs: Set<Item.ID> = []
}

@MainActor
@Observable
final class Store {
	var lists: [RandomList]
	var combos: [Combo]

	init(lists: [RandomList], combos: [Combo]) {
		self.lists = lists
		self.combos = combos
	}

	subscript(id: Combo.ID) -> Combo {
		get { combos.first { $0.id == id } ?? Combo(name: "?") }
		set {
			guard let index = combos.firstIndex(where: { $0.id == id }) else { return }
			combos[index] = newValue
		}
	}

	func list(_ id: RandomList.ID) -> RandomList? { lists.first { $0.id == id } }

	/// Member Lists in the Combo's own order, skipping any that have been deleted.
	func members(of combo: Combo) -> [RandomList] { combo.listIDs.compactMap(list) }

	/// Every Item of every member List, flattened. No Item dedup — repetition is weighting.
	func pool(of combo: Combo) -> [(list: RandomList, item: Item)] {
		members(of: combo).flatMap { list in list.items.map { (list, $0) } }
	}

	static func sample() -> Store {
		let lunch = RandomList(
			name: "Lunch",
			emoji: "🥪",
			items: ["Pret", "The noodle place", "Leftovers", "Pizza", "Pizza"].map { Item(title: $0) }
		)
		let dinner = RandomList(
			name: "Dinner",
			emoji: "🍝",
			// This List is a Deck mid-run. A Combo containing it must ignore that entirely.
			drawMode: .deck,
			items: [
				Item(title: "Carbonara", isDealt: true),
				Item(title: "Katsu curry"),
				Item(title: "Fajitas", isDealt: true),
				Item(title: "Roast"),
			]
		)
		let takeaway = RandomList(
			name: "Takeaway",
			emoji: "🥡",
			items: ["Thai", "Curry", "Chip shop"].map { Item(title: $0) }
		)
		let films = RandomList(
			name: "Films to rewatch",
			emoji: "🎬",
			items: ["Heat", "Paddington 2", "The Thing", "Aliens", "Jurassic Park"].map { Item(title: $0) }
		)
		let games = RandomList(
			name: "Board games",
			emoji: "🎲",
			items: ["Wingspan", "Azul", "Codenames", "Carcassonne", "Root"].map { Item(title: $0) }
		)
		let walks = RandomList(name: "Weekend walks", emoji: "🥾", items: [])
		let chores = RandomList(name: "Chores", items: ["Bins", "Hoover", "Washing up"].map { Item(title: $0) })

		let mealtimes = Combo(
			name: "What's for tea",
			emoji: "🍽️",
			listIDs: [lunch.id, dinner.id, takeaway.id]
		)
		// A Combo Deck part-way through: three of its twelve pooled Items dealt.
		let fridayNight = Combo(
			name: "Friday night",
			emoji: "🍿",
			drawMode: .deck,
			listIDs: [films.id, games.id, takeaway.id],
			dealtItemIDs: Set([films.items[0].id, games.items[1].id, takeaway.items[2].id])
		)
		// No members yet — the state you land in straight after creating one.
		let empty = Combo(name: "Weekend", emoji: "🗓️")
		// Members, but none of them have any Items.
		let allEmpty = Combo(name: "Big day out", emoji: "🚶", listIDs: [walks.id])

		return Store(
			lists: [lunch, dinner, takeaway, films, games, walks, chores],
			combos: [mealtimes, fridayNight, empty, allEmpty]
		)
	}

	/// First launch: Lists exist (you made them on the Lists tab) but no Combos yet.
	static func empty() -> Store {
		let sample = Store.sample()
		return Store(lists: sample.lists, combos: [])
	}

	/// The other empty state: no Lists at all, so there is nothing to combine.
	static func noLists() -> Store { Store(lists: [], combos: []) }
}
