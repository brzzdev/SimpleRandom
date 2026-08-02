//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import Database
internal import Dependencies
internal import DependenciesTestSupport
internal import Foundation
internal import Models
internal import SQLiteData
internal import Testing

// `@testable` for the pool, which is `internal` on the feature's state — the sheet's own view
// is the only thing in the app that reads it.
@testable internal import RandomiseFeature

/// The draw: uniform selection over a seeded generator (#21).
///
/// One in-memory database per test case, built by the real `migrator`, and one ``LCRNG`` per
/// test case seeded the same way — a suite trait's value is evaluated per case, so no test
/// inherits a generator another has already advanced.
///
/// **These tests assert domain properties, never a literal pick.** A test that writes down
/// the Item `LCRNG(seed: 0)` happens to choose is a test of this generator's arithmetic; the
/// claims worth making are that the result comes from the pool, that a one-item List always
/// returns that Item, that a repeat is legal, and that a title appearing twice is drawn twice
/// as often.
///
/// Those last three are claims about *many* draws, and no single `send` can state the pick it
/// is about to make. They are therefore asserted against ``RandomiseFeature/State/draw()``
/// directly, which is where selection lives — rather than by turning a `TestStore`'s
/// exhaustive comparison off, which ADR-0019 rules out and which would have bought a discount
/// on a cost this app is not paying. Every `TestStore` here stays exhaustive.
///
/// Seeded rows carry **negative** ids, as ``DatabaseTests`` and ``ListsFeatureTests`` do:
/// `inMemory()` registers a counting generator that mints `…0001` upwards, so a negative seed
/// cannot collide with one it mints.
@MainActor
@Suite(
	.dependency(\.defaultDatabase, try inMemory()),
	.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(LCRNG(seed: 0))),
)
internal struct RandomiseFeatureTests {
	@Test
	internal func theOpeningResultIsDrawnAsTheSheetIsBuilt() async throws {
		let pool = try await seedLunch(with: ["Pizza", "Ramen", "Tacos"])
		let state = RandomiseFeature.State(scope: .list(UUID(-1)))

		// The pool is state rather than something assembled at draw time and discarded, in
		// `(createdAt, id)` order — the sheet holds every candidate, not just the winner
		// (ADR-0021).
		#expect(state.pool == pool)

		// Drawn before the sheet's view exists, which is what leaves the token already moved at
		// presentation and so keeps the haptic and the announcement to re-rolls only (ADR-0017).
		#expect(state.drawToken == 1)
		#expect(try pool.contains(#require(state.result)))
		#expect(state.canDrawAgain)
	}

	@Test
	internal func aOneItemListAlwaysDrawsThatItem() async throws {
		let pool = try await seedLunch(with: ["Pizza"])
		let pizza = try #require(pool.first)
		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(UUID(-1)))) {
			RandomiseFeature()
		}

		// A one-item List randomises normally and always returns that Item — no minimum, and no
		// special case in the reducer (ADR-0004).
		#expect(store.result == pizza)

		// **Again** is disabled here, where every draw is a repeat by definition and the haptic
		// would be the only thing distinguishing a working button from a broken one (ADR-0017).
		#expect(store.canDrawAgain == false)

		// The button being disabled is the courtesy; this is what the reducer does anyway. The
		// result cannot move, so the token is the only thing that does — which is the whole
		// reason it exists.
		store.send(.againButtonTapped) {
			$0.drawToken = 2
		}
	}

	@Test
	internal func thePoolHoldsOnlyTheScopedListsItems() async throws {
		let lunch = try await seedLunch(with: ["Pizza", "Ramen"])
		try await database.write { db in
			try db.seed {
				Models.List(id: UUID(-2), createdAt: .seed, name: "Films")
				Item(id: UUID(-99), createdAt: .earlier, listID: UUID(-2), title: "Alien")
			}
		}

		// The other List's Item is older than both of these, so it would sort first — and be
		// drawable — if the query were not scoped. An Item belongs to exactly one List.
		let state = RandomiseFeature.State(scope: .list(UUID(-1)))
		#expect(state.pool == lunch)
	}

	@Test
	internal func anEmptyPoolDrawsNothing() async throws {
		try await database.write { db in
			try db.seed { Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch") }
		}

		// An empty List is legal — you have just made it — and the pinned bar is disabled, so
		// this state is unreachable through the UI. It is asserted anyway because the alternative
		// to returning nothing is trapping on an empty pool.
		let state = RandomiseFeature.State(scope: .list(UUID(-1)))
		#expect(state.pool.isEmpty)
		#expect(state.result == nil)
		#expect(state.drawToken == 0)
		#expect(state.canDrawAgain == false)
	}

	@Test
	internal func everyDrawComesFromThePoolAndMovesTheToken() async throws {
		let pool = try await seedLunch(with: ["Pizza", "Ramen", "Tacos"])
		var state = RandomiseFeature.State(scope: .list(UUID(-1)))

		// What a draw promises, held over enough of them that a picker reaching outside the pool
		// or a token that only moves when the result does would have to show itself. The opening
		// draw already moved the token to 1, so the next is 2.
		for draw in 2...20 {
			state.draw()
			#expect(state.drawToken == draw)
			#expect(state.result.map(pool.contains) == true)
		}
	}

	@Test
	internal func theSameItemTwiceInARowIsLegalAndNotSuppressed() async throws {
		try await seedLunch(with: ["Pizza", "Ramen"])
		var state = RandomiseFeature.State(scope: .list(UUID(-1)))

		// A plain List has no memory: repeats are not merely tolerated, they are the reason the
		// sheet acknowledges a re-roll at all, since one landing on the Item already shown is
		// otherwise indistinguishable from a dead button (ADR-0017). Over a coin flip's worth of
		// draws a run of two is a near-certainty, and a suppressing implementation could never
		// produce one.
		var previous = state.result
		var repeats = 0
		for _ in 1...40 {
			state.draw()
			if state.result == previous { repeats += 1 }
			previous = state.result
		}
		#expect(repeats > 0)
	}

	@Test
	internal func aTitleAppearingTwiceIsDrawnTwiceAsOften() async throws {
		// Repetition is the user's own weighting mechanism: selection is uniform over *Items*,
		// nothing is deduplicated, and `weight` is reserved and read by nothing (ADR-0004).
		try await seedLunch(with: ["Pizza", "Pizza", "Ramen"])
		var state = RandomiseFeature.State(scope: .list(UUID(-1)))

		let draws = 600
		var counts: [String: Int] = [:]
		for _ in 1...draws {
			state.draw()
			counts[state.result?.title ?? "", default: 0] += 1
		}

		// Both bounds, generously: the claim is that Pizza is drawn about twice as often as
		// Ramen, and either a picker that deduplicated titles or one that was not uniform would
		// fall outside. The generator is seeded, so this is deterministic rather than flaky — it
		// either passes on every run or fails on every run.
		let pizza = counts["Pizza", default: 0]
		let ramen = counts["Ramen", default: 0]
		#expect(pizza + ramen == draws)
		#expect(Double(pizza) > Double(ramen) * 1.6)
		#expect(Double(pizza) < Double(ramen) * 2.5)
	}
}

// MARK: - Reading and seeding

extension RandomiseFeatureTests {
	/// The in-memory database the suite trait handed this test case.
	private var database: any DatabaseWriter {
		Dependency(\.defaultDatabase).wrappedValue
	}

	/// Seeds `Lunch` with the given titles and hands back its Items in the pool's own order, so
	/// a test can say "from the pool" without restating what the pool is.
	///
	/// Not the shared fixture ADR-0019 rules out. The thing that varies between these worlds is
	/// the titles, and every caller states its own at the call site — `["Pizza", "Pizza",
	/// "Ramen"]` is the whole subject of the duplicate-weighting test. What is hidden is only
	/// the List and the ids, which no test here is about.
	///
	/// Read back rather than returned as written. The titles share a `createdAt`, so what
	/// separates them is the id tie-break, and whether `UUID(-1)` collates before `UUID(-2)` is
	/// SQLite's business rather than something a test should assert by assuming it.
	@discardableResult
	private func seedLunch(with titles: [String]) async throws -> [Item] {
		try await database.write { db in
			try db.seed {
				Models.List(id: UUID(-1), createdAt: .seed, name: "Lunch")

				for (offset, title) in titles.enumerated() {
					Item(id: UUID(-1 - offset), createdAt: .seed, listID: UUID(-1), title: title)
				}
			}
		}
		return try await database.read { db in
			try Item.where { $0.listID.eq(UUID(-1)) }.order { ($0.createdAt, $0.id) }.fetchAll(db)
		}
	}
}

extension Date {
	/// The one instant these worlds are seeded at. Nothing here reads a clock — a draw is not
	/// recorded in v1, and the pool's order is settled by the id tie-break.
	internal static let seed = Date(timeIntervalSince1970: 1_234_567_890)

	/// A minute before ``seed``, for the row that must sort ahead of the pool to prove the
	/// query is scoped.
	internal static let earlier = seed.addingTimeInterval(-60)
}
