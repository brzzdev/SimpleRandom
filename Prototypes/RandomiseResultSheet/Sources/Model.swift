// PROTOTYPE — throwaway. Answers https://github.com/brzzdev/SimpleRandom/issues/11
// In-memory only. No SQLiteData, no TCA, no persistence: this is about what it looks like.

import SwiftUI

struct PoolItem: Identifiable, Hashable {
	let id = UUID()
	var title: String
	/// Set only on the Combine path — #7 requires the result to name the source List.
	var sourceEmoji: String?
	var sourceName: String?
	var isDealt = false
}

enum DrawMode: String, CaseIterable, Hashable {
	case independent = "Plain"
	case deck = "Deck"
}

/// One presentation of the sheet. Created when Randomise is tapped, thrown away on dismiss —
/// #6 settled that nothing about a draw is persisted beyond the deck's dealt state.
@MainActor
@Observable
final class Session: Identifiable {
	let id = UUID()
	/// The List or Combo the draw came from.
	let scopeName: String
	let scopeEmoji: String?
	let drawMode: DrawMode
	/// True on the Combine path, where a result has to say which List it came from.
	let showsSource: Bool

	var pool: [PoolItem]
	private(set) var current: PoolItem?
	/// Increments on every draw, including one that lands on the same Item. The trigger for
	/// haptics, and the only thing that reliably changes when a re-roll repeats itself.
	private(set) var drawCount = 0
	private(set) var isExhausted = false

	init(scopeName: String, scopeEmoji: String?, drawMode: DrawMode, showsSource: Bool, pool: [PoolItem]) {
		self.drawMode = drawMode
		self.pool = pool
		self.scopeEmoji = scopeEmoji
		self.scopeName = scopeName
		self.showsSource = showsSource
	}

	var total: Int { pool.count }
	var remaining: Int { pool.count(where: { !$0.isDealt }) }

	/// Opening the sheet is itself a draw, and restarts the per-presentation counter.
	func open() {
		drawCount = 0
		draw()
	}

	func draw() {
		switch drawMode {
		case .independent:
			guard let pick = pool.randomElement() else { return }
			current = pick
		case .deck:
			guard let index = pool.indices.filter({ !pool[$0].isDealt }).randomElement() else {
				current = nil
				isExhausted = true
				return
			}
			pool[index].isDealt = true
			current = pool[index]
		}
		drawCount += 1
	}

	func reshuffle() {
		for index in pool.indices { pool[index].isDealt = false }
		isExhausted = false
		draw()
	}
}

// MARK: - Scenarios

/// The cases worth judging the sheet against. Each builds a fresh `Session`.
enum Scenario: String, CaseIterable, Identifiable {
	case plain = "Plain · 6 items"
	case single = "Plain · 1 item"
	case longText = "Plain · long text"
	case deck = "Deck · 3 of 5 left"
	case deckLastCard = "Deck · 1 left"
	case combo = "Combo · Food"

	var id: Self { self }

	/// What the screen behind the sheet is: a List detail, or a Combo detail.
	var backdropTitle: String {
		switch self {
		case .combo: "Food"
		case .deck, .deckLastCard: "Films to rewatch"
		case .longText: "Weekend plans"
		case .plain: "Lunch"
		case .single: "Who does the washing up"
		}
	}

	@MainActor
	func makeSession() -> Session {
		switch self {
		case .combo:
			Session(
				scopeName: "Food",
				scopeEmoji: "🍽️",
				drawMode: .independent,
				showsSource: true,
				// "Pizza" appears in both member Lists — #7 does not deduplicate, so provenance
				// is the only thing telling the two results apart.
				pool: [
					PoolItem(title: "Pret", sourceEmoji: "🥪", sourceName: "Lunch"),
					PoolItem(title: "The noodle place", sourceEmoji: "🥪", sourceName: "Lunch"),
					PoolItem(title: "Pizza", sourceEmoji: "🥪", sourceName: "Lunch"),
					PoolItem(title: "Pizza", sourceEmoji: "🍝", sourceName: "Dinner"),
					PoolItem(title: "Roast", sourceEmoji: "🍝", sourceName: "Dinner"),
					PoolItem(title: "Whatever is in the fridge", sourceEmoji: "🍝", sourceName: "Dinner"),
				]
			)

		case .deck:
			Session(
				scopeName: "Films to rewatch",
				scopeEmoji: "🎬",
				drawMode: .deck,
				showsSource: false,
				pool: [
					PoolItem(title: "Heat", isDealt: true),
					PoolItem(title: "Paddington 2"),
					PoolItem(title: "The Thing"),
					PoolItem(title: "Aliens", isDealt: true),
					PoolItem(title: "Jurassic Park"),
				]
			)

		case .deckLastCard:
			Session(
				scopeName: "Films to rewatch",
				scopeEmoji: "🎬",
				drawMode: .deck,
				showsSource: false,
				pool: [
					PoolItem(title: "Heat", isDealt: true),
					PoolItem(title: "Paddington 2"),
					PoolItem(title: "The Thing", isDealt: true),
					PoolItem(title: "Aliens", isDealt: true),
					PoolItem(title: "Jurassic Park", isDealt: true),
				]
			)

		case .longText:
			Session(
				scopeName: "Weekend plans",
				scopeEmoji: "🥾",
				drawMode: .independent,
				showsSource: false,
				pool: [
					PoolItem(title: "Walk the whole of the Thames Path from Richmond out to Hampton Court and back"),
					PoolItem(title: "Nothing at all"),
					PoolItem(title: "Antidisestablishmentarianism"),
				]
			)

		case .plain:
			Session(
				scopeName: "Lunch",
				scopeEmoji: "🥪",
				drawMode: .independent,
				showsSource: false,
				// Two "Pizza"s and six items: re-rolling repeats often. That is the point —
				// #6 deliberately refused to suppress immediate repeats.
				pool: ["Pret", "The noodle place", "Leftovers", "Pizza", "Pizza", "Whatever is in the fridge"]
					.map { PoolItem(title: $0) }
			)

		case .single:
			Session(
				scopeName: "Who does the washing up",
				scopeEmoji: nil,
				drawMode: .independent,
				showsSource: false,
				pool: [PoolItem(title: "Paul")]
			)
		}
	}
}
