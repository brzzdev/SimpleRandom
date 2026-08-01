// PROTOTYPE — throwaway. Answers https://github.com/brzzdev/SimpleRandom/issues/10
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

@MainActor
@Observable
final class Store {
	var lists: [RandomList]

	init(lists: [RandomList]) {
		self.lists = lists
	}

	subscript(id: RandomList.ID) -> RandomList {
		get { lists.first { $0.id == id } ?? RandomList(name: "?") }
		set {
			guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
			lists[index] = newValue
		}
	}

	static func sample() -> Store {
		Store(lists: [
			RandomList(
				name: "Lunch",
				emoji: "🥪",
				items: ["Pret", "The noodle place", "Leftovers", "Pizza", "Pizza", "Whatever is in the fridge"]
					.map { Item(title: $0) }
			),
			RandomList(
				name: "Films to rewatch",
				emoji: "🎬",
				drawMode: .deck,
				items: [
					Item(title: "Heat", isDealt: true),
					Item(title: "Paddington 2"),
					Item(title: "The Thing"),
					Item(title: "Aliens", isDealt: true),
					Item(title: "Jurassic Park"),
				]
			),
			RandomList(name: "Who does the washing up", items: ["Paul", "Sam"].map { Item(title: $0) }),
			RandomList(name: "Weekend walks", emoji: "🥾", items: []),
			RandomList(
				name: "Board games",
				emoji: "🎲",
				items: ["Wingspan", "Azul", "Codenames", "Carcassonne", "Ticket to Ride", "Root", "Scythe", "7 Wonders"]
					.map { Item(title: $0) }
			),
		])
	}

	static func empty() -> Store { Store(lists: []) }
}
