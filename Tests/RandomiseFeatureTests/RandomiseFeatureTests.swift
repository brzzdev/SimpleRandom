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
///
/// A Deck's draws are the exception to the rule above, in one direction only: with a single
/// undealt Item left the pick is forced, and a forced pick is a fact rather than the
/// generator's arithmetic. Where more than one card is live the claim stays relational —
/// whatever came out is out of the pool, and everything else is still in it.
///
/// The clock is frozen because a draw row is stamped with one. Nothing here reads it back.
@MainActor
@Suite(
	.dependency(\.date, .constant(.seed)),
	.dependency(\.defaultDatabase, try inMemory()),
	.dependency(\.withRandomNumberGenerator, WithRandomNumberGenerator(LCRNG(seed: 0))),
)
internal struct RandomiseFeatureTests {
	@Test
	internal func constructingTheStateDrawsNothing() async throws {
		let (lunch, pool) = try await seedLunch(with: ["Pizza", "Ramen", "Tacos"])

		// A `State` is inert until it is mounted. The pool is there — it is state rather than
		// something assembled at draw time and discarded, in `(createdAt, id)` order, so the
		// sheet holds every candidate and not just the winner (ADR-0021) — but the pick is the
		// feature's work, and the feature has not run yet.
		//
		// This is what keeps the generator honest: a `State` built in a preview, or anywhere
		// else outside a store's dependency scope, cannot quietly draw from the live one.
		let state = RandomiseFeature.State(scope: .list(lunch))
		#expect(state.pool == pool)
		#expect(state.result == nil)
		#expect(state.drawToken == 0)
	}

	@Test
	internal func mountingDrawsTheOpeningResultAndAOneItemListAlwaysDrawsThatItem() async throws {
		let (lunch, pool) = try await seedLunch(with: ["Pizza"])
		let pizza = try #require(pool.first)
		// Mounting draws the opening result, asserted through the initialiser's own `changes`
		// closure because that is when it happens — the store has mounted the feature before it
		// hands itself back. A one-item List randomises normally and always returns that Item —
		// no minimum, and no special case in the reducer (ADR-0004) — which is what makes the
		// pick here something a test may write down.
		//
		// ``ListDetailTests/theDetailIsWhatPresentsTheRandomiseSheet`` pins the half that matters
		// more: that this lands inside the presenting `send`, and so before the sheet's view
		// exists, which is what keeps the haptic and the announcement to re-rolls only
		// (ADR-0017).
		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(lunch))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .item(pizza)
		}

		// **Again** is disabled here, where every draw is a repeat by definition and the haptic
		// would be the only thing distinguishing a working button from a broken one (ADR-0017).
		#expect(store.canDrawAgain == false)

		// The button being disabled is the courtesy; this is what the reducer does anyway. The
		// result cannot move, so the token is the only thing that does — which is the whole
		// reason it exists.
		store.send(.againButtonTapped) {
			$0.drawToken = 2
		}

		// And neither draw recorded anything. A plain List has no memory to keep, so the deck's
		// table stays empty however often it is drawn — the pool above never shrank either.
		#expect(try await draws().isEmpty)
	}

	@Test
	internal func thePoolHoldsOnlyTheScopedListsItems() async throws {
		let (lunch, pool) = try await seedLunch(with: ["Pizza", "Ramen"])
		try await database.write { db in
			try db.seed {
				Models.List(id: UUID(-2), createdAt: .seed, name: "Films")
				Item(id: UUID(-99), createdAt: .earlier, listID: UUID(-2), title: "Alien")
			}
		}

		// The other List's Item is older than both of these, so it would sort first — and be
		// drawable — if the query were not scoped. An Item belongs to exactly one List.
		let state = RandomiseFeature.State(scope: .list(lunch))
		#expect(state.pool == pool)
	}

	@Test
	internal func anEmptyPoolDrawsNothing() async throws {
		let (lunch, _) = try await seedLunch(with: [])

		// An empty List is legal — you have just made it — and the pinned bar is disabled, so
		// this state is unreachable through the UI. It is asserted anyway because the alternative
		// to returning nothing is trapping on an empty pool. Mounted, so the opening draw has
		// had its chance and declined it.
		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(lunch))) {
			RandomiseFeature()
		}
		#expect(store.pool.isEmpty)
		#expect(store.result == nil)
		#expect(store.drawToken == 0)
		#expect(store.canDrawAgain == false)
	}

	@Test
	internal func everyDrawComesFromThePoolAndMovesTheToken() async throws {
		let (lunch, pool) = try await seedLunch(with: ["Pizza", "Ramen", "Tacos"])
		var state = RandomiseFeature.State(scope: .list(lunch))

		// What a draw promises, held over enough of them that a picker reaching outside the pool
		// or a token that only moves when the result does would have to show itself. Unmounted,
		// so this counts from the first draw rather than from the opening one.
		for draw in 1...20 {
			state.draw()
			#expect(state.drawToken == draw)
			#expect(state.result?.item.map(pool.contains) == true)
		}
	}

	@Test
	internal func theSameItemTwiceInARowIsLegalAndNotSuppressed() async throws {
		let (lunch, _) = try await seedLunch(with: ["Pizza", "Ramen"])
		var state = RandomiseFeature.State(scope: .list(lunch))

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
		let (lunch, _) = try await seedLunch(with: ["Pizza", "Pizza", "Ramen"])
		var state = RandomiseFeature.State(scope: .list(lunch))

		let draws = 600
		var counts: [String: Int] = [:]
		for _ in 1...draws {
			state.draw()
			counts[state.result?.item?.title ?? "", default: 0] += 1
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

// MARK: - Deck mode

extension RandomiseFeatureTests {
	@Test
	internal func aDeckDrawsOnlyOverWhatItHasNotDealt() async throws {
		let (deck, pool) = try await seedLunch(
			.deck,
			with: ["Pizza", "Ramen", "Tacos"],
			dealing: ["Pizza", "Ramen"],
		)
		let tacos = try #require(pool.last)

		// The row's existence *is* the draw, so two rows leave one card: a Deck draws only over
		// the Items with no `ListDraw` row (ADR-0006).
		#expect(RandomiseFeature.State(scope: .list(deck)).pool == [tacos])

		// The very same rows, read by the very same List turned plain. Switching a Deck back to
		// plain preserves its rows and draws over everything regardless — which is what lets
		// switching back resume where it left off rather than start again.
		let plain = Models.List(id: deck.id, createdAt: deck.createdAt, name: deck.name)
		#expect(RandomiseFeature.State(scope: .list(plain)).pool == pool)
	}

	@Test
	internal func computingTheWinnerDealsNothingOnItsOwn() async throws {
		let (deck, _) = try await seedLunch(.deck, with: ["Pizza", "Ramen", "Tacos"])
		var state = RandomiseFeature.State(scope: .list(deck))

		// The pick and the deal are separate: `draw()` chooses a winner and nothing else, and
		// the row is written where the result becomes *visible*, by the feature. In v1 the two
		// are the same instant, so only this can tell them apart — and it is the constraint a
		// v2 reveal animation depends on, because a row written at the tap spends a card the
		// user never saw when the sheet is dragged away mid-animation (ADR-0021).
		state.draw()
		#expect(state.result?.item != nil)
		#expect(try await draws().isEmpty)
	}

	@Test
	internal func aDeckNeverDealsACardItHasAlreadyDealtHoweverStaleThePoolIs() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza", "Ramen"])
		var state = RandomiseFeature.State(scope: .list(deck))

		// Unmounted, so nothing records these draws and the pool never shrinks: this is exactly
		// the state a re-roll meets when it arrives before the row the last deal is writing has
		// landed. The deck's own rule holds against it — a card it has dealt is spent, whatever
		// the pool still says.
		//
		// **Three draws, not two.** The window is as deep as the user can tap, not one deal
		// deep: every draw arriving before the writes land sees the same unshrunk pool. An
		// earlier version filtered only the card on screen, which survived the second draw and
		// dealt the first card again on the third — the sheet showing a card the deck had spent,
		// and on the Combine path a second `ComboDraw` row landing silently for it, since
		// `comboDraws` is keyed on a surrogate id.
		state.draw()
		let first = try #require(state.result?.item)
		state.draw()
		let second = try #require(state.result?.item)

		#expect(first != second)
		#expect(Set([first, second]) == Set(pool))
		#expect(state.dealt == Set(pool.map(\.id)))

		// The third finds nothing left to deal and lands on exhaustion, off a pool that is still
		// showing both cards. That is the correct answer: the deck is spent even though the
		// database has not been told yet.
		state.draw()
		#expect(state.result == .exhausted)
		#expect(state.pool == pool)
		#expect(state.drawToken == 3)
	}

	@Test
	internal func aDeckReshuffledOnAnotherDeviceIsDealableAgainWithoutClosingTheSheet() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza", "Ramen"], dealing: ["Pizza"])
		let ramen = try #require(pool.last)

		// Resumed one card in, so the opening draw is the last card this Deck has.
		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.dealt = [ramen.id]
			$0.drawToken = 1
			$0.result = .item(ramen)
		}
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			// The row has landed and the pool has caught up, so this sheet's own note about the
			// card has nothing left to say — the query is the record now.
			$0.dealt = []
			$0.pool = []
		}

		// The other iPhone reshuffles. Not a gesture this sheet owns: the rows go, and the pool
		// refills underneath it through the observation.
		try await database.write { db in
			try ListDraw.inList(UUID(-1)).delete().execute(db)
		}
		// Read rather than `expect`ed: nothing was sent, so there is no action whose changes this
		// could be. The refresh travels in the next assertion's closure instead.
		try await store.state.$pool.load()
		#expect(store.pool == pool)

		// **The deck is dealable again, with the sheet still open.** `dealt` is what the draw
		// filters against, so a set that outlived its write window would hold both cards here
		// and answer "That's the whole deck" over a full pool — contradicting the rule that
		// Reshuffle puts the cards back *everywhere*, and leaving this device stuck until the
		// sheet closed.
		#expect(store.canDrawAgain)
		store.send(.againButtonTapped) {
			$0.dealt = store.dealt
			$0.drawToken = 2
			$0.pool = pool
			$0.result = store.result
		}
		let dealt = try #require(store.result?.item)
		#expect(pool.contains(dealt))
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = []
			$0.pool = pool.filter { $0.id != dealt.id }
		}
	}

	@Test
	internal func aPlainListKeepsNoMemoryOfWhatItHasDrawn() async throws {
		let (lunch, _) = try await seedLunch(with: ["Pizza", "Ramen"])
		var state = RandomiseFeature.State(scope: .list(lunch))

		// The other side of the rule above: nothing is spent on the plain path, so the filter has
		// nothing to filter and repeats stay legal (ADR-0004). Asserted because `dealt` is the
		// one piece of state that could quietly turn a plain List into a Deck.
		for _ in 1...10 { state.draw() }
		#expect(state.dealt.isEmpty)
	}

	@Test
	internal func dealingAnItemWritesItsRowAndTakesItOutOfThePool() async throws {
		let (deck, pool) = try await seedLunch(
			.deck,
			with: ["Pizza", "Ramen", "Tacos"],
			dealing: ["Pizza", "Ramen"],
		)
		let tacos = try #require(pool.last)

		// One card live, so the pick is forced and this may be written down.
		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.dealt = [tacos.id]
			$0.drawToken = 1
			$0.result = .item(tacos)
		}

		// The pool shrinks by one on every draw, because the row the draw wrote takes the Item it
		// dealt back out of the query the pool is. That churn is what keeping the pool in state
		// costs, and it is asserted rather than hidden (ADR-0021).
		//
		// It travels in this closure because the deal announces itself: `dealSettled` is sent
		// once the write has landed *and* the pool has been reloaded, so the two changes belong
		// to one action and the test no longer has to reach for `settle(_:)` to see them.
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = []
			$0.pool = []
		}

		// The whole deck has now been dealt exactly once, two of them by the seed and this one
		// by the feature: the multiset of what came out *is* the pool.
		#expect(try await Set(draws()) == Set(pool.map(\.id)))
	}

	@Test
	internal func theDrawAfterADecksLastCardExhaustsItAndReshuffleDealsItAgain() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza", "Ramen"], dealing: ["Pizza"])
		let ramen = try #require(pool.last)

		// Resumed one card in, so the opening draw is the last one this Deck has.
		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.dealt = [ramen.id]
			$0.drawToken = 1
			$0.result = .item(ramen)
		}
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = []
			$0.pool = []
		}

		// Exhaustion lands on the draw *after* the last card, not on the last card itself: the
		// result stays up until a re-roll goes looking for one that is not there. The token
		// moves with it, because that replacement is what the announcement acknowledges.
		#expect(store.canDrawAgain)
		store.send(.againButtonTapped) {
			$0.drawToken = 2
			$0.result = .exhausted
		}
		// Exhaustion spends nothing — there was nothing to spend — so nothing is recorded and
		// no deal settles.
		#expect(store.dealt.isEmpty)

		// Reshuffle deletes every row belonging to this List's Items and deals from the deck it
		// has just put back. Nothing here changes synchronously: the delete, the refill and the
		// draw that follows all belong to the effect.
		await store.send(.reshuffleButtonTapped)?.value
		await store.receive(\.deckReshuffled, timeout: .seconds(1)) {
			$0.drawToken = 3
			// Two cards are live again, so which one comes out is the generator's business and
			// not this suite's. Read from the store rather than written down; the claims worth
			// making are the two `#expect`s below and the pool the deal leaves behind.
			//
			// Reshuffle empties what this sheet has spent before dealing, so this holds the one
			// card just dealt and not the one dealt before it — otherwise the put-back cards
			// would still be filtered out and the reshuffle would deal into exhaustion.
			$0.dealt = store.dealt
			$0.result = store.result
			$0.pool = pool
		}
		#expect(store.dealt == Set(store.result?.item.map { [$0.id] } ?? []))

		let dealt = try #require(store.result?.item)
		#expect(pool.contains(dealt))

		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = []
			$0.pool = pool.filter { $0.id != dealt.id }
		}
		// One row, for the card just dealt: Reshuffle put both of the old ones back.
		#expect(try await draws() == [dealt.id])
	}

	@Test
	internal func dealingRightThroughADeckProducesEveryCardExactlyOnce() async throws {
		// Four cards, two of them sharing a title: a Deck deals Items rather than titles, so
		// "Pizza" twice is two cards and comes out twice. That is what makes this a claim
		// about a multiset rather than a set — the same reason repetition is the user's own
		// weighting mechanism on the plain path (ADR-0004).
		let titles = ["Pizza", "Pizza", "Ramen", "Tacos"]
		let (deck, pool) = try await seedLunch(.deck, with: titles, dealing: titles)

		// Seeded spent, so that the one draw a test cannot state — the opening one, which
		// happens synchronously at mount — is the one draw whose outcome is not a pick.
		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .exhausted
		}

		// Reshuffle puts the whole deck back and deals the first card of the run.
		await store.send(.reshuffleButtonTapped)?.value
		await store.receive(\.deckReshuffled, timeout: .seconds(1)) {
			$0.drawToken = 2
			// Emptied by the reshuffle, then holding the one card it dealt straight afterwards.
			$0.dealt = store.dealt
			$0.result = store.result
			$0.pool = pool
		}
		var dealt = [try #require(store.result?.item)]
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = []
			$0.pool = pool.filter { !dealt.contains($0) }
		}

		// Then right through to the last card. Which card each draw lands on is the generator's
		// business, and so is whether the row that removes it has landed by the time the store
		// is asked — both are read from it rather than written down. The claims are the two
		// underneath: no card comes out twice, and the pool is always the deck minus what has
		// been dealt.
		for draw in 2...pool.count {
			store.send(.againButtonTapped) {
				$0.drawToken = draw + 1
				$0.dealt = store.dealt
				$0.result = store.result
				$0.pool = store.pool
			}
			let card = try #require(store.result?.item)
			#expect(!dealt.contains(card))
			dealt.append(card)

			// Each deal settles before the next tap, which is what keeps `dealt` down to the
			// in-flight window rather than accumulating the whole run. The pool it leaves behind
			// is the deck minus everything dealt so far.
			await store.receive(\.dealSettled, timeout: .seconds(1)) {
				$0.dealt = []
				$0.pool = pool.filter { !dealt.contains($0) }
			}
		}

		#expect(dealt.count == pool.count)
		#expect(Set(dealt) == Set(pool))
		#expect(dealt.map(\.title).sorted() == titles.sorted())
		#expect(try await Set(draws()) == Set(pool.map(\.id)))
		// And the sheet is holding nothing of its own: every deal has settled, so the table is
		// the whole record. A set still carrying the run would be the thing that outvotes a
		// Reshuffle arriving from another device.
		#expect(store.dealt.isEmpty)

		// And exhaustion lands on the draw after the last card — N + 1, never N.
		store.send(.againButtonTapped) {
			$0.drawToken = pool.count + 2
			$0.result = .exhausted
			$0.pool = []
		}
	}

	@Test
	internal func aOneItemDeckExhaustsAfterASingleDraw() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza"])
		let pizza = try #require(pool.first)

		let store = TestStore(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.dealt = [pizza.id]
			$0.drawToken = 1
			$0.result = .item(pizza)
		}
		await store.receive(\.dealSettled, timeout: .seconds(1)) {
			$0.dealt = []
			$0.pool = []
		}
		#expect(try await draws() == [pizza.id])

		// **Again** stays live where a plain one-item List disables it. No draw of a Deck's is a
		// repeat — this one either deals a card or lands on exhaustion — and disabling it here
		// would make "That's the whole deck" unreachable, since it is only ever reached from
		// inside this sheet.
		#expect(store.canDrawAgain)
		store.send(.againButtonTapped) {
			$0.drawToken = 2
			$0.result = .exhausted
			$0.pool = []
		}
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
	/// A builder rather than the shared fixture ADR-0019 rules out — the distinction that ADR
	/// now draws explicitly. The thing that varies between these worlds is the titles, and every
	/// caller states its own at the call site; `["Pizza", "Pizza", "Ramen"]` is the whole
	/// subject of the duplicate-weighting test. Only the List and the ids are hidden, and no
	/// test here is about those.
	///
	/// Read back rather than returned as written. The titles share a `createdAt`, so what
	/// separates them is the id tie-break, and whether `UUID(-1)` collates before `UUID(-2)` is
	/// SQLite's business rather than something a test should assert by assuming it.
	@discardableResult
	private func seedLunch(
		_ drawMode: DrawMode = .independent,
		with titles: [String],
		dealing dealtTitles: [String] = [],
	) async throws -> (list: Models.List, pool: [Item]) {
		let lunch = Models.List(id: UUID(-1), createdAt: .seed, drawMode: drawMode, name: "Lunch")
		try await database.write { db in
			try db.seed {
				lunch

				for (offset, title) in titles.enumerated() {
					Item(id: UUID(-1 - offset), createdAt: .seed, listID: UUID(-1), title: title)
				}
			}

			// Rows for a deck that was already running when the sheet opened. Seeded rather than
			// dealt, because what these worlds need is a Deck part-way through, not a second
			// implementation of dealing one.
			for (offset, title) in titles.enumerated() where dealtTitles.contains(title) {
				try ListDraw.insert { ListDraw(itemID: UUID(-1 - offset), createdAt: .seed) }.execute(db)
			}
		}
		let pool = try await database.read { db in
			try Item.where { $0.listID.eq(UUID(-1)) }.order { ($0.createdAt, $0.id) }.fetchAll(db)
		}
		return (lunch, pool)
	}

	/// Every Item this List has dealt, straight from the table.
	private func draws() async throws -> [Item.ID] {
		try await database.read { db in
			try ListDraw.inList(UUID(-1)).order { ($0.createdAt, $0.itemID) }.select { $0.itemID }.fetchAll(db)
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
