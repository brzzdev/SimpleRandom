//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

internal import ComposableArchitecture2
internal import CustomDump
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
/// directly, which is where selection lives — rather than by turning a `TestStoreActor`'s
/// exhaustive comparison off, which ADR-0019 rules out and which would have bought a discount
/// on a cost this app is not paying. Every `TestStoreActor` here stays exhaustive.
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
///
/// The suite is not `@MainActor` and its stores are ``TestStoreActor``s: no module here sets
/// `defaultIsolation`, so these features are not main-actor-isolated and the actor-isolated
/// harness is the one the library points a package of this shape at (#64).
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
		expectNoDifference(state.pool, pool)
		#expect(state.result == nil)
		expectNoDifference(state.drawToken, 0)
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
		let store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(lunch))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .item(pizza)
		}

		// **Again** is disabled here, where every draw is a repeat by definition and the haptic
		// would be the only thing distinguishing a working button from a broken one (ADR-0017).
		#expect(await store.canDrawAgain == false)

		// The button being disabled is the courtesy; this is what the reducer does anyway. The
		// result cannot move, so the token is the only thing that does — which is the whole
		// reason it exists.
		await store.send(.againButtonTapped) {
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
		expectNoDifference(state.pool, pool)
	}

	@Test
	internal func anEmptyPoolDrawsNothing() async throws {
		let (lunch, _) = try await seedLunch(with: [])

		// An empty List is legal — you have just made it — and the pinned bar is disabled, so
		// this state is unreachable through the UI. It is asserted anyway because the alternative
		// to returning nothing is trapping on an empty pool. Mounted, so the opening draw has
		// had its chance and declined it.
		let store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(lunch))) {
			RandomiseFeature()
		}
		#expect(await store.pool.isEmpty)
		#expect(await store.result == nil)
		let drawToken = await store.drawToken
		expectNoDifference(drawToken, 0)
		#expect(await store.canDrawAgain == false)
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
			expectNoDifference(state.drawToken, draw)
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
		expectNoDifference(pizza + ramen, draws)
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
		expectNoDifference(RandomiseFeature.State(scope: .list(deck)).pool, [tacos])

		// The very same rows, read by the very same List turned plain. Switching a Deck back to
		// plain preserves its rows and draws over everything regardless — which is what lets
		// switching back resume where it left off rather than start again.
		let plain = Models.List(id: deck.id, createdAt: deck.createdAt, name: deck.name)
		expectNoDifference(RandomiseFeature.State(scope: .list(plain)).pool, pool)
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
	internal func aDeckDrawsFromThePoolAndNothingElseRemembersWhatItDealt() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza", "Ramen"])
		var state = RandomiseFeature.State(scope: .list(deck))

		// Unmounted, so nothing records these draws and the pool never shrinks — and the deck
		// therefore deals from two live cards every time. **That is the design, not a defect
		// this test tolerates**: the pool is the only record of what has been dealt, and the
		// feature never draws from a pool that a write in flight has not caught up with,
		// because it refuses to draw at all while one is (ADR-0024).
		//
		// `draw()` is the pick and nothing more, which is what makes it assertable this way.
		for _ in 1...10 {
			state.draw()
			#expect(state.result?.item.map(pool.contains) == true)
		}
		expectNoDifference(state.drawToken, 10)
		expectNoDifference(state.pool, pool)
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
		let store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .item(tacos)
		}

		try await settle(store)
		// The pool shrinks by one on every draw, because the row the draw wrote takes the Item
		// it dealt back out of the query the pool is. That churn is what keeping the pool in
		// state costs, and it is asserted rather than hidden (ADR-0021).
		//
		// Read rather than `expect`ed: a `@FetchAll` drives no assertion of its own, and
		// nothing else has moved here for it to be compared alongside — the same rule
		// ``ListsFeatureTests`` states in full. Where a later draw *does* move something, the
		// pool travels in that assertion's closure.
		#expect(await store.pool.isEmpty)

		// The whole deck has now been dealt exactly once, two of them by the seed and this one
		// by the feature: the multiset of what came out *is* the pool.
		let dealtIDs = try await Set(draws())
		expectNoDifference(dealtIDs, Set(pool.map(\.id)))
	}

	@Test
	internal func theDrawAfterADecksLastCardExhaustsItAndReshuffleDealsItAgain() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza", "Ramen"], dealing: ["Pizza"])
		let ramen = try #require(pool.last)

		// Resumed one card in, so the opening draw is the last one this Deck has.
		let store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .item(ramen)
		}
		try await settle(store)
		#expect(await store.pool.isEmpty)

		// Exhaustion lands on the draw *after* the last card, not on the last card itself: the
		// result stays up until a re-roll goes looking for one that is not there. The token
		// moves with it, because that replacement is what the announcement acknowledges.
		#expect(await store.canDrawAgain)
		await store.send(.againButtonTapped) {
			$0.drawToken = 2
			$0.result = .exhausted
			// The draw that emptied it moved nothing else, so this is where that refresh is
			// compared: a snapshot carries the whole state, whatever caused it to be taken.
			$0.pool = []
		}

		// Reshuffle deletes every row belonging to this List's Items and deals from the deck it
		// has just put back. Nothing here changes synchronously: the delete, the refill and the
		// draw that follows all belong to the effect.
		await store.send(.reshuffleButtonTapped)?.value
		await store.receive(\.deckReshuffled, timeout: .seconds(1)) {
			$0.drawToken = 3
			// Two cards are live again, so which one comes out is the generator's business and
			// not this suite's. Read from the store rather than written down; the claims worth
			// making are the `#expect`s below and the pool the deal leaves behind.
			//
			// The pool is the whole deck again by the time this draw happens: the delete landed
			// and the reload waited for it, which is the one thing that makes a spent card live
			// again.
			$0.result = store.actual(\.result)
			$0.pool = pool
		}

		let dealt = try #require(await store.result?.item)
		#expect(pool.contains(dealt))

		try await settle(store)
		let remaining = await store.pool
		expectNoDifference(remaining, pool.filter { $0.id != dealt.id })
		// One row, for the card just dealt: Reshuffle put both of the old ones back.
		let dealtIDs = try await draws()
		expectNoDifference(dealtIDs, [dealt.id])
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
		let store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .exhausted
		}

		// Reshuffle puts the whole deck back and deals the first card of the run.
		await store.send(.reshuffleButtonTapped)?.value
		await store.receive(\.deckReshuffled, timeout: .seconds(1)) {
			$0.drawToken = 2
			// The whole deck, put back by the delete this action follows, less nothing: the card
			// it deals is taken out by the insert that has not run yet.
			$0.result = store.actual(\.result)
			$0.pool = pool
		}
		var dealt = [try #require(await store.result?.item)]
		try await settle(store)

		// Then right through to the last card. Which card each draw lands on is the generator's
		// business and is read from the store rather than written down. The claims are the two
		// underneath: no card comes out twice, and the pool is always the deck minus what has
		// been dealt.
		//
		// **Each draw's task is awaited before the next tap.** That is not a convenience: the
		// deal's write and the reload that follows it are what make the pool authoritative, and
		// the feature refuses a tap arriving before they finish (ADR-0024). Awaiting is what a
		// user tapping at human speed does, and what the run below is about.
		for draw in 2...pool.count {
			await store.send(.againButtonTapped) {
				$0.drawToken = draw + 1
				$0.result = store.actual(\.result)
				$0.pool = store.actual(\.pool)
			}?.value
			let card = try #require(await store.result?.item)
			#expect(!dealt.contains(card))
			dealt.append(card)

			try await settle(store)
			let remaining = await store.pool
			expectNoDifference(remaining, pool.filter { !dealt.contains($0) })
		}

		expectNoDifference(dealt.count, pool.count)
		expectNoDifference(Set(dealt), Set(pool))
		expectNoDifference(dealt.map(\.title).sorted(), titles.sorted())
		let dealtIDs = try await Set(draws())
		expectNoDifference(dealtIDs, Set(pool.map(\.id)))

		// And exhaustion lands on the draw after the last card — N + 1, never N.
		await store.send(.againButtonTapped) {
			$0.drawToken = pool.count + 2
			$0.result = .exhausted
			$0.pool = []
		}
	}

	@Test
	internal func aOneItemDeckExhaustsAfterASingleDraw() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza"])
		let pizza = try #require(pool.first)

		let store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .item(pizza)
		}
		try await settle(store)
		#expect(await store.pool.isEmpty)
		let dealtIDs = try await draws()
		expectNoDifference(dealtIDs, [pizza.id])

		// **Again** stays live where a plain one-item List disables it. No draw of a Deck's is a
		// repeat — this one either deals a card or lands on exhaustion — and disabling it here
		// would make "That's the whole deck" unreachable, since it is only ever reached from
		// inside this sheet.
		#expect(await store.canDrawAgain)
		await store.send(.againButtonTapped) {
			$0.drawToken = 2
			$0.result = .exhausted
			$0.pool = []
		}
	}

	@Test
	internal func aReshuffleOnAnotherDeviceReachesAnOpenSheet() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza"])
		let pizza = try #require(pool.first)

		let store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(deck))) {
			RandomiseFeature()
		} changes: {
			$0.drawToken = 1
			$0.result = .item(pizza)
		}
		try await settle(store)
		#expect(await store.pool.isEmpty)

		// The sheet is spent, and stays that way until something puts the cards back.
		await store.send(.againButtonTapped) {
			$0.drawToken = 2
			$0.result = .exhausted
			// The opening deal emptied it. Nothing else moved at the time, so this is where that
			// refresh is compared: a snapshot carries the whole state, whatever caused it.
			$0.pool = []
		}

		// **Reshuffle, from somewhere this sheet cannot see.** Deck state syncs, so the rows can
		// go while the sheet is open — from another device, or from the detail screen's own
		// toolbar Reshuffle on this one. Written straight to the table rather than through the
		// feature, because the point is that nothing told the sheet.
		try await database.write { db in
			try ListDraw.inList(deck.id).delete().execute(db)
		}
		try await store.loadPool()

		// And the sheet simply believes the pool — the card is back on offer, and the draw is
		// forced onto it. This is what the earlier local guard could not do: it kept filtering
		// these cards out and answered "That's the whole deck" over a full deck for as long as
		// the sheet stayed open (ADR-0024).
		await store.send(.againButtonTapped) {
			$0.drawToken = 3
			$0.result = .item(pizza)
			// Read back rather than written down. This draw refills the pool and then empties it
			// again from its own task, and which side of that the comparison lands on is a race —
			// pinning it to the full deck passes alone and fails under load. The claims worth
			// making are the forced pick above and the two below, none of which are timing's
			// business.
			$0.pool = store.actual(\.pool)
		}?.value
		#expect(await store.pool.isEmpty)
		let dealtIDs = try await draws()
		expectNoDifference(dealtIDs, [pizza.id])
	}

	@Test
	internal func aWriteThatFailsLeavesItsCardInTheDeck() async throws {
		let (deck, pool) = try await seedLunch(.deck, with: ["Pizza"])
		let pizza = try #require(pool.first)
		try await refuseDraws()

		// A Deck whose insert throws. `withErrorReporting` reports it and the deal ends there —
		// so the row is never written, and a card is spent only by a row that exists (ADR-0006).
		// The report *is* the expected outcome here, which is what `withKnownIssue` says: the
		// pick and the sheet are correct, and the database is the thing that failed.
		// **The construction is inside the region, not just the settle.** The opening deal runs at
		// mount, and its failure is reported before `TestStore.init` hands the store back — so a
		// region covering only the wait below sees no issue and fails with "Known issue was not
		// recorded". That is what forces the store to be declared first and assigned here.
		var store: TestStoreActor<RandomiseFeature>!
		await withKnownIssue {
			store = await TestStoreActor(initialState: RandomiseFeature.State(scope: .list(deck))) {
				RandomiseFeature()
			} changes: {
				$0.drawToken = 1
				$0.result = .item(pizza)
			}
			try await settle(store)
		}

		// Nothing persisted, so nothing was spent: the pool still holds the card and the deck is
		// exactly as full as its row count says it is.
		#expect(try await draws().isEmpty)
		let afterTheFailedDeal = await store.pool
		expectNoDifference(afterTheFailedDeal, pool)

		// **And the card is still on offer.** This is the half that regressed under the local
		// guard, which inserted into its own set before the write started and removed nothing on
		// the failure path — so a one-card Deck reported exhaustion at a row count of zero,
		// contradicting the rule that a Deck is exhausted when its row count equals its pool
		// (ADR-0024). Degraded state is the write failure's doing; the deck's arithmetic is not
		// allowed to be wrong as well.
		await withKnownIssue {
			await store.send(.againButtonTapped) {
				$0.drawToken = 2
				$0.result = .item(pizza)
			}?.value
		}
		#expect(try await draws().isEmpty)
		let afterTheFailedReRoll = await store.pool
		expectNoDifference(afterTheFailedReRoll, pool)
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

	/// Makes every future insert into `listDraws` throw, and nothing else.
	///
	/// A trigger rather than a closed or read-only database, because the reads have to keep
	/// working: the pool is a live query over the very table this leaves alone, and a test about
	/// a failed *write* that also broke the pool would prove nothing about which of the two put
	/// the card back.
	private func refuseDraws() async throws {
		try await database.write { db in
			try db.execute(
				sql: """
					CREATE TRIGGER "refuseDraws" BEFORE INSERT ON "listDraws"
					BEGIN SELECT RAISE(ABORT, 'the write failed'); END
					"""
			)
		}
	}

	/// Every Item this List has dealt, straight from the table.
	private func draws() async throws -> [Item.ID] {
		try await database.read { db in
			try ListDraw.inList(UUID(-1)).order { ($0.createdAt, $0.itemID) }.select { $0.itemID }.fetchAll(db)
		}
	}

	/// Waits for a deal the feature started, then hands the pool the world it left behind.
	///
	/// A draw's row is written from a task, so a test that read the pool straight afterwards
	/// would be racing it. The empty write queues behind that insert on the same serialised
	/// writer, which is what makes the wait a fact rather than a sleep; the load is the same
	/// ``ListDetailTests/reloadItems(_:)`` asks for, because a database observation arrives on
	/// its own schedule too.
	private func settle(_ store: TestStoreActor<RandomiseFeature>) async throws {
		try await database.write { _ in }
		try await store.loadPool()
	}
}

// MARK: - Reaching an actor-isolated store

extension TestStoreActor {
	/// The store's live value for a piece of state, read from inside a `changes` closure.
	///
	/// Those closures are synchronous, so `await store.result` is unavailable in one — and the
	/// isolation is not merely assumed: `send` and `receive` are isolated to this store and call
	/// the closure themselves, so it runs on this store's own executor.
	///
	/// Used only where the value is the generator's business rather than this suite's, exactly
	/// as ``TestStore`` allowed the same read before #64. Every other field still travels
	/// written down.
	nonisolated internal func actual<Value: Sendable>(
		_ keyPath: sending KeyPath<State, Value>
	) -> Value {
		assumeIsolated { $0.state[keyPath: keyPath] }
	}
}

extension TestStoreActor where Subject == RandomiseFeature {
	/// Reloads the pool, from off the store's actor.
	///
	/// `state` is isolated and `RandomiseFeature.State` is not `Sendable`, so it cannot be
	/// lifted out to reach the query on it. An isolated method reaches it in place instead and
	/// hands back nothing.
	internal func loadPool() async throws {
		try await state.$pool.load()
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
