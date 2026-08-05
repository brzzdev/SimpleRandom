//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import Models

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// The randomise sheet, and the whole draw — the pool, the pick and the token the
/// acknowledgement fires on (#21).
///
/// Both tabs present it, and it owns the draw rather than just its presentation: its state
/// carries a ``DrawScope`` and the pick happens here, so one implementation and one test
/// suite cover both surfaces (ADR-0016).
///
/// Both draw modes run through here. A plain List has no memory — the same Item twice in a
/// row is legal and is not suppressed (ADR-0004) — while a Deck draws only over Items with
/// no ``ListDraw`` row, inserts one for the Item it deals, and offers **Reshuffle** once
/// there are none left (#22).
///
/// A Combo pools every Item of every member List and draws uniformly across the lot, so a
/// 100-item List dominates a 3-item one in a Combo they share (#24). It names the source List
/// above the result, which is load-bearing rather than decorative: duplicate Items are not
/// deduplicated, so two "Pizza"s are otherwise indistinguishable.
///
/// A Combo Deck deals against ``ComboDraw`` rows of its own, and the two surfaces' decks are
/// independent in both directions: drawing here reads and writes no ``ListDraw`` row, and an
/// exhausted member List still contributes its Items to the pool (#25, ADR-0007). The only
/// difference between the two paths below is which table the row goes in.
@Feature
public struct RandomiseFeature {
	public struct State {
		/// What the sheet is showing: a dealt Item, or a Deck that has run out.
		///
		/// One value rather than an Item beside an `isExhausted` flag, because the two cases
		/// are exclusive — "That's the whole deck" replaces the result rather than joining it,
		/// and a pair of properties could be made to disagree.
		public enum Result: Hashable, Sendable {
			case exhausted
			case item(Item)

			/// The Item this is showing, if it is showing one. The sheet's own view switches
			/// over both cases; this is for the places that only care about the one.
			public var item: Item? {
				guard case .item(let item) = self else { return nil }
				return item
			}
		}

		/// The cards a deal of this sheet's is still in flight for, each against the
		/// ``drawToken`` of the draw that dealt it.
		///
		/// **A Deck's pool is a live query, and the row that removes a dealt card is written from
		/// a task**, so between a deal and its write landing the pool still offers cards the deck
		/// has spent. This is what the draw filters against, and it has to hold every card in that
		/// window: filtering only the card on screen survives one stale draw and not two, so a
		/// third rapid tap on a two-card deck dealt the first card again.
		///
		/// **An entry ends when the deal that made it learns what happened — not when the pool
		/// stops offering the card.** A deal learns in two of the three ways it can end, and both
		/// mean *unguard*:
		///
		/// - **The write failed.** Nothing was spent, so the card belongs back in the deck.
		/// - **The write committed and the reload landed.** ``pool`` is fresh, so it is now the
		///   authority: if it has dropped the card the guard is redundant, and if it is *offering*
		///   the card then another device has reshuffled and genuinely put it back. Deck state
		///   syncs, and Reshuffle puts the cards back everywhere — outvoting that from here is
		///   what left an earlier version answering "That's the whole deck" over a full pool.
		///
		/// The third way is a write that committed under a reload that **threw**, and it is the
		/// only one that keeps the guard: the pool is stale, so nothing fresh says whether the
		/// card is spent, and the safe direction is to assume it is. That entry is left for
		/// ``dropGuardsThePoolNoLongerOffers()`` to clear, because the deal that made it has
		/// already ended and will never speak again.
		///
		/// **The token is what makes an entry belong to one deal**, and it is load-bearing rather
		/// than defensive. A deal from before a Reshuffle can land after the Reshuffle has put the
		/// deck back and dealt the same card again; keyed on the Item alone, that late arrival
		/// would clear a guard belonging to a deal still in flight, and the next tap could deal
		/// the card twice.
		///
		/// Empty on the plain path, where nothing is spent and a repeat is legal (ADR-0004).
		private(set) internal var dealt: [Item.ID: Int] = [:]

		/// Incremented on every draw and rendered by nothing.
		///
		/// A re-roll landing on the Item already shown changes no other state, so this is the
		/// only value the sheet's haptic and its VoiceOver announcement can trigger on
		/// (ADR-0017). Not persisted — nothing about a draw is.
		///
		/// The opening draw happens on mount, and `.ifLet` mounts a child inside the presenting
		/// `send` — the library drains its post-processing hooks before `send` returns — so the
		/// token is already `1` by the time SwiftUI presents the sheet. Neither channel fires on
		/// presentation, because there is no change for the view to see: announcing there would
		/// talk over the result the user is being shown.
		///
		/// The contract is the *reveal* rather than the pick — in v1 they are the same instant,
		/// and anything that later separates them moves this increment rather than leaving it
		/// where the name suggests (ADR-0021).
		private(set) public var drawToken = 0

		/// Every candidate in scope, not just the winner — and in a Deck, only the ones it has
		/// left to deal.
		///
		/// A `@FetchAll` built from the scope, rather than a pool assembled in the reducer at
		/// draw time and discarded: this feature is a sheet child whose view can see no other
		/// state, so anything later cycling the pool has to find it here (ADR-0021).
		///
		/// A Deck's pool therefore shrinks by one on every draw, because the row the draw
		/// writes takes the Item it dealt back out of this query. That churn is the cost of
		/// keeping the pool in state, and the test suite's exhaustive assertions carry it.
		@FetchAll internal var pool: [Item]

		/// What the sheet is showing. `nil` only for an empty pool that is not a Deck's, which
		/// the pinned bar's disabled state means the user cannot reach.
		private(set) public var result: Result?

		public let scope: DrawScope

		/// The Lists a Combo pools from, so the sheet can name the one the result came from.
		///
		/// Empty on the Lists path, where the sheet says nothing about provenance — which is
		/// what lets ``sourceList`` read it without asking the scope first.
		///
		/// The member Lists rather than a join onto the pool: the pool is `[Item]` on both
		/// paths, and widening it to carry a source would make the Lists path pay for a column
		/// it never renders.
		@FetchAll internal var sourceLists: [Models.List]

		/// **Again** is disabled on a one-item pool, where every draw is a repeat by definition
		/// and the haptic would be the only thing distinguishing a working button from a broken
		/// one (ADR-0017).
		///
		/// A Deck is exempt: no draw of its is a repeat, because each one either deals a card
		/// that has not been dealt or lands on exhaustion — which is the only way into "That's
		/// the whole deck", since the detail screen's pinned button already reshuffles a spent
		/// Deck rather than opening this sheet. Once it is exhausted, **Reshuffle** has replaced
		/// **Again** and nothing reads this.
		public var canDrawAgain: Bool {
			scope.drawMode == .deck || pool.count > 1
		}

		/// The member List the drawn Item came from — the secondary line above the result on the
		/// Combine path, and the provenance the re-roll announcement carries.
		///
		/// Load-bearing rather than decoration: draw results are not persisted and duplicate
		/// Items are not deduplicated, so "Pizza" from Lunch and "Pizza" from Dinner would
		/// otherwise be indistinguishable.
		///
		/// `nil` on the Lists path without a branch on the scope, because ``sourceLists`` is
		/// empty there — a List's result has one possible source and the sheet says nothing
		/// about it. `nil` for an exhausted Deck too, which has no Item to have come from
		/// anywhere.
		public var sourceList: Models.List? {
			guard let listID = result?.item?.listID else { return nil }
			return sourceLists.first { $0.id == listID }
		}

		public init(scope: DrawScope) {
			self.scope = scope
			switch scope {
			case .combo(let combo):
				// Every Item of every member List, flattened — minus, for a Deck, the ones this
				// Combo has already dealt. A member List's own `drawMode` and `ListDraw` rows are
				// consulted by neither branch: an Item exhausted within its own List is still in
				// this pool (ADR-0007).
				let candidates =
					switch combo.drawMode {
					case .deck: Item.undealt(inCombo: combo.id)
					case .independent: Item.inCombo(combo.id)
					}
				// `(createdAt, id)` ascending is the app's one sort order, applied across the
				// pooled rows rather than per member, so the pool is the same sequence on every
				// device.
				_pool = FetchAll(candidates.order { ($0.createdAt, $0.id) })
				_sourceLists = FetchAll(Models.List.inCombo(combo.id))

			case .list(let list):
				// A Deck draws only over what it has not dealt; a plain List draws over everything,
				// including rows left behind by a Deck it used to be — switching back to plain
				// preserves them, and switching back to a Deck resumes where it left off.
				let candidates =
					switch list.drawMode {
					case .deck: Item.undealt(in: list.id)
					case .independent: Item.inList(list.id)
					}
				// `(createdAt, id)` ascending is the app's one sort order. Selection is uniform, so
				// the order does not change the odds — it is what makes the pool the same sequence
				// on every device, which is what a v2 animation over it would need.
				_pool = FetchAll(candidates.order { ($0.createdAt, $0.id) })
				// A List's result has one possible source and the sheet does not name it, so there
				// is nothing to look up — empty, rather than a query returning the one row nothing
				// reads.
				_sourceLists = FetchAll(Models.List.none)
			}
		}

		/// Picks uniformly from the pool and acknowledges it by moving ``drawToken``.
		///
		/// Uniform across the Items in scope and nothing else: `weight` is reserved and read by
		/// nothing, and adding the same text twice is the user's own weighting mechanism
		/// (ADR-0004). A one-item pool therefore always returns that Item.
		///
		/// Drops every guard the pool has stopped offering, which is only ever safe to call with
		/// a pool that has just been reloaded.
		///
		/// A card a *fresh* pool no longer offers has a committed row behind it, so the query
		/// refuses it unaided and the guard is redundant — whichever deal made it. That is what
		/// makes this safe alongside ``dealSettled(_:from:)`` rather than a second, conflicting
		/// rule: it only ever drops what is already refused, so it cannot clear a guard that is
		/// doing work.
		///
		/// It exists for the one entry ``dealt`` cannot settle on its own — a write that
		/// committed under a reload that threw, whose deal has ended without ever learning the
		/// outcome. Without this, that guard would outlive its window for the life of the sheet,
		/// and a Reshuffle arriving from another device would be filtered out over a full pool.
		internal mutating func dropGuardsThePoolNoLongerOffers() {
			let offered = Set(pool.map(\.id))
			dealt = dealt.filter { offered.contains($0.key) }
		}

		/// Unguards a card because the deal that guarded it has learnt what happened.
		///
		/// The token is checked rather than trusted: a deal that lands after a Reshuffle has
		/// re-dealt the same card is settling a guard that no longer exists, and clearing the
		/// *current* one would leave the card drawable while its own write is still in flight.
		/// Comparing the token makes a late arrival a no-op instead.
		internal mutating func dealSettled(_ itemID: Item.ID, from generation: Int) {
			guard dealt[itemID] == generation else { return }
			dealt[itemID] = nil
		}

		/// Forgets what this sheet has dealt, because Reshuffle has just deleted the rows that
		/// recorded it.
		///
		/// Paired with the delete rather than folded into ``draw()``: the draw's job is to refuse
		/// a spent card, and the only thing that unspends one is the rows going. This clears the
		/// whole set rather than waiting for each ``poolCaughtUp(with:)``, because a reshuffle in
		/// flight has already deleted every row those ids were waiting on.
		internal mutating func putTheDeckBack() {
			dealt = [:]
		}

		/// Lives on `State` so that the opening draw and a re-roll are literally the same pick —
		/// one arrives on mount, the other on an action, and both are the feature's own logic
		/// rather than a client behind a seam, which is what lets a test seed the generator and
		/// assert a real draw (ADR-0011).
		internal mutating func draw() {
			@Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

			// Lifted out of the closure: `pool` is a property of an `inout self` here, and the
			// generator's closure is `@Sendable`.
			//
			// **A Deck never deals a card it has already dealt, whatever the pool still says.**
			// The pool is a live query and the row that takes a dealt Item out of it is written
			// from a task, so every draw arriving before those writes land sees cards the deck
			// has spent. The rule is the deck's own, applied to the state that has not caught up
			// with it yet — and it is applied to ``dealt`` rather than to the card on screen,
			// because the screen holds one card and the window holds as many as the user can tap
			// through. Filtering the shown card alone survived one stale draw and not two.
			let isDeck = scope.drawMode == .deck
			let candidates = isDeck ? pool.filter { dealt[$0.id] == nil } : pool
			guard let drawn = withRandomNumberGenerator({ generator in
				candidates.randomElement(using: &generator)
			}) else {
				// A Deck with nothing left to deal is exhausted, and says so in place of the
				// result. The token moves because that *is* the reveal — the element an
				// announcement would otherwise re-read has ceased to exist, so the exhausted case
				// has to speak for itself (ADR-0017).
				//
				// A plain List or Combo draws nothing and says nothing here. Its pool is empty
				// only when the List — or every member List — is, and the pinned bar is disabled
				// then, so the user cannot reach it.
				guard isDeck else { return }
				result = .exhausted
				drawToken += 1
				return
			}

			result = .item(drawn)
			drawToken += 1
			// Guarded here rather than in ``RandomiseFeature/deal(_:)``, which is where the *row*
			// is written: the row records the deal for every future sitting, and this stops this
			// one dealing the card again in the window before that row lands. Against the token
			// this draw has just taken, so the guard belongs to this deal and no other. A plain
			// List or Combo guards nothing — repeats are legal there, and are the reason the
			// sheet acknowledges a re-roll at all (ADR-0004, ADR-0017).
			if isDeck { dealt[drawn.id] = drawToken }
		}
	}

	public enum Action {
		case againButtonTapped
		/// The deck is back, so deal from it. Sent by ``reshuffleAndDeal(_:)`` once the delete
		/// has landed and the pool has been refilled — never by the view.
		case deckReshuffled
		/// The pool has just been reloaded, so guards it no longer offers can go. Sent by
		/// ``deal(_:)`` — never by the view — after a reload that landed.
		///
		/// Sweeps up after the one case ``dealSettled(itemID:generation:)`` cannot reach: a deal
		/// whose write committed under a reload that threw ends without settling, so some *later*
		/// deal's reload is the only thing left to notice its card is gone.
		case poolReloaded
		/// A deal has learnt what happened to it, so the card it guarded can be unguarded. Sent
		/// by ``deal(_:)`` — never by the view — on a write that failed, and on a write that
		/// committed with a reload behind it that landed. **Not** sent when the reload threw: see
		/// ``State/dealt``.
		///
		/// It carries the ``State/drawToken`` of the draw that dealt the card, because a deal can
		/// land after a Reshuffle has re-dealt the same card and must not clear that newer guard.
		case dealSettled(itemID: Item.ID, generation: Int)
		case reshuffleButtonTapped
	}

	/// The in-flight reshuffle, so a second tap can be told there is one.
	@StoreTaskID var reshuffle

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .againButtonTapped:
				// In place, with no memory of the last result: a plain List may deal the same Item
				// twice in a row, and nothing suppresses it. A Deck cannot repeat, because the
				// draw below is over what it has not dealt.
				state.draw()
				deal(state)

			case let .dealSettled(itemID, generation):
				state.dealSettled(itemID, from: generation)

			case .poolReloaded:
				state.dropGuardsThePoolNoLongerOffers()

			case .deckReshuffled:
				// The cards are back in the database, so they are back in this sheet's reckoning
				// too — before the draw, or every card the deck just put back would still be
				// filtered out of it and the reshuffle would deal straight back into exhaustion.
				// The delete this follows is the one thing that makes a spent card live again.
				state.putTheDeckBack()
				state.draw()
				deal(state)

			case .reshuffleButtonTapped:
				reshuffleAndDeal(state)
			}
		}
		// The opening result. On mount rather than in `State.init` so that the pick is the
		// feature's own work on both paths, and so that it runs inside the store's dependency
		// scope — a `State` built in a preview would otherwise have drawn from the live
		// generator at construction. `.ifLet` mounts a child within the presenting `send`, which
		// is what keeps this ahead of the sheet's view. See ``State/drawToken``.
		.onMount { state in
			state.draw()
			deal(state)
		}
	}

	/// Records the draw — the row whose existence *is* the deal (ADR-0006).
	///
	/// Called wherever a draw has just been revealed, rather than inside ``State/draw()``
	/// where the winner is computed. In v1 those are the same instant, so this constrains
	/// nothing today; it matters the moment anything sits between them, because a v2 reveal
	/// animation that wrote the row at the tap would spend a card the user never saw if the
	/// sheet were dragged away mid-animation. A Deck may not deal behind the user's back
	/// (ADR-0021).
	private func deal(_ state: State) {
		// Two things have to hold: this is a Deck, because a plain List or Combo has no memory
		// to keep, and it is showing an Item, because an exhausted Deck has nothing to record.
		guard
			state.scope.drawMode == .deck,
			case .item(let item) = state.result
		else { return }

		@Dependency(\.date.now) var now
		@Dependency(\.defaultDatabase) var database
		let pool = state.$pool
		// Lifted out: the task outlives this call, and `State` is not the thing to send into it
		// — the scope is a value, and it is the whole of what the write needs.
		let scope = state.scope
		// The token of the draw that just dealt this card, so the settlement below can say which
		// deal it is settling. See ``State/dealt``.
		let generation = state.drawToken
		store.addTask {
			// `Void?` is spelled out because the closure returns nothing, and an inferred `()?`
			// is a warning.
			//
			// **The write and the reload are reported separately, because their failures mean
			// opposite things.** A write that never committed spent nothing, so the card belongs
			// back in the deck; a write that committed under a reload that threw leaves the pool
			// stale, with nothing fresh to say whether the card is spent.
			let committed: Void? = await withErrorReporting {
				try await database.write { db in
					// One row per dealt Item on both paths — the same mechanism in two tables,
					// because an Item belongs to exactly one List and to any number of Combos
					// (ADR-0006). A Combo writes **only** its own row: a member List's own deck is
					// left exactly as it was, which is ADR-0007 seen from this side.
					switch scope {
					case .combo(let combo):
						try ComboDraw
							.insert { ComboDraw.Draft(comboID: combo.id, createdAt: now, itemID: item.id) }
							.execute(db)

					case .list:
						try ListDraw.insert { ListDraw(itemID: item.id, createdAt: now) }.execute(db)
					}
				}
			}
			guard committed != nil else {
				// Nothing was spent, so the card goes straight back into the deck. Leaving it
				// guarded would shrink the deck by a card the database never recorded, and take
				// it to "That's the whole deck" over a card it had never dealt.
				try store.send(.dealSettled(itemID: item.id, generation: generation))
				return
			}

			// The pool is a live query, and the observation that takes the dealt Item out of it
			// arrives on its own schedule. Waiting for it here is what stops the next draw seeing
			// a card that has already gone.
			let reloaded: Void? = await withErrorReporting {
				try await pool.load()
			}
			// A reload that threw leaves the pool stale, and the guard is all that stands between
			// a committed card and being dealt twice — so it stays, and a later reload settles
			// it. Every other outcome unguards: the pool is fresh, and fresh is authoritative
			// even when it hands the card back, because that means another device reshuffled.
			guard reloaded != nil else { return }
			try store.send(.dealSettled(itemID: item.id, generation: generation))
			// And a sweep, because this deal can only speak for its own card. A guard left behind
			// by a deal whose reload threw has no one else to clear it, and the pool this reload
			// produced is the first fresh evidence since.
			try store.send(.poolReloaded)
		}
	}

	/// Puts the whole deck back, then deals from it.
	///
	/// Not gated on exhaustion: Reshuffle is available at any time, and this is the same work
	/// whether the deck is spent or barely touched. It deals afterwards because the button
	/// sits where **Again** was, and a button in that position produces a result.
	private func reshuffleAndDeal(_ state: State) {
		// Not a second time while the first is still in flight. Each tap would otherwise
		// put the deck back and deal from it independently, so two would deal twice — the
		// second landing on a card the user never asked for, or, on a one-card deck, straight
		// back on "That's the whole deck" a moment after the card appeared.
		//
		// Deliberately untested, for the reason ``ItemEditor`` gives about its own guard: a
		// `TestStore` runs the first effect to completion before it delivers the second action,
		// so a test written against this passes with the guard removed.
		guard !reshuffle.isRunning else { return }

		@Dependency(\.defaultDatabase) var database
		// Lifted out for the reason ``deal(_:)`` gives, and the same value: which table to
		// delete from, and which id names the rows.
		let scope = state.scope
		let pool = state.$pool
		store.addTask(id: reshuffle) {
			// `Void?` is spelled out because the closure returns nothing, and an inferred `()?`
			// is a warning.
			let reshuffled: Void? = await withErrorReporting {
				try await database.write { db in
					// A hard delete of the whole set on either path, which is what makes Reshuffle
					// the exact inverse of the rows the deals wrote (ADR-0006). A Combo puts back
					// its own cards and only its own: it never touches a member List's rows, and a
					// member List's Reshuffle never touches its (ADR-0007).
					switch scope {
					case .combo(let combo): try ComboDraw.inCombo(combo.id).delete().execute(db)
					case .list(let list): try ListDraw.inList(list.id).delete().execute(db)
					}
				}
				// The draw that follows has to see the deck put back rather than race the
				// observation that refills the pool, so this asks for it and waits.
				try await pool.load()
			}
			// A failed delete leaves the deck exactly as it was. Dealing anyway would land on
			// exhaustion again and read as a dead button.
			guard reshuffled != nil else { return }
			try store.send(.deckReshuffled)
		}
	}
}
