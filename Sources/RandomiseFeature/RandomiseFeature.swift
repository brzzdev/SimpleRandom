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
/// deduplicated, so two "Pizza"s are otherwise indistinguishable. A Combo's *own* deck state
/// — the ``ComboDraw`` rows a Combo Deck deals against — arrives with #25.
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
			dealsAsDeck || pool.count > 1
		}

		/// Whether this sheet actually deals as a Deck — which is `drawMode` on the Lists path,
		/// and **`false` on the Combine one whatever the Combo says**, until #25.
		///
		/// A Combo Deck's rows are `ComboDraw`'s, and nothing here writes or reads one yet. Left
		/// to `scope.drawMode` alone, such a Combo would take the Deck branch of ``draw()``,
		/// re-roll into "That's the whole deck" off a pool that never shrinks, and offer a
		/// **Reshuffle** that ``reshuffleAndDeal(_:)`` refuses — a dead button on a screen with
		/// no other way out. Dealing plainly is the honest interim: repeats are legal, nothing is
		/// recorded, and every button on the sheet does what it says.
		///
		/// ``DrawScope/drawMode`` stays truthful — it reads the record, and the form really did
		/// set that mode. This is the one place that says what the *sheet* can honour, and #25
		/// deletes it rather than editing it.
		internal var dealsAsDeck: Bool {
			guard case .list = scope else { return false }
			return scope.drawMode == .deck
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
				// A Combo Deck's own `ComboDraw` rows — the pool that excludes them, the deal that
				// writes one, and the Reshuffle that deletes them — arrive with #25. Until then it
				// pools and draws like a plain Combo and records nothing, which is a Deck that is
				// not dealing: reported rather than left to look deliberate.
				if combo.drawMode == .deck {
					reportIssue("A Combo Deck keeps no deck state yet — `ComboDraw` arrives with #25.")
				}
				// Every Item of every member List, flattened. `(createdAt, id)` ascending is the
				// app's one sort order, applied across the pooled rows rather than per member, so
				// the pool is the same sequence on every device.
				_pool = FetchAll(Item.inCombo(combo.id).order { ($0.createdAt, $0.id) })
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
		/// Lives on `State` so that the opening draw and a re-roll are literally the same pick —
		/// one arrives on mount, the other on an action, and both are the feature's own logic
		/// rather than a client behind a seam, which is what lets a test seed the generator and
		/// assert a real draw (ADR-0011).
		internal mutating func draw() {
			@Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

			// Lifted out of the closure: `pool` is a property of an `inout self` here, and the
			// generator's closure is `@Sendable`.
			//
			// A Deck never deals the card it is showing. Its pool is a live query and the row
			// that takes the dealt Item out of it is written from a task, so a re-roll that
			// arrives before that lands would otherwise see a card the deck has already spent —
			// and deal it a second time. The rule is the deck's own, applied to the state that
			// has not caught up with it yet.
			let showing = result?.item?.id
			let candidates = dealsAsDeck ? pool.filter { $0.id != showing } : pool
			guard let drawn = withRandomNumberGenerator({ generator in
				candidates.randomElement(using: &generator)
			}) else {
				// A Deck with nothing left to deal is exhausted, and says so in place of the
				// result. The token moves because that *is* the reveal — the element an
				// announcement would otherwise re-read has ceased to exist, so the exhausted case
				// has to speak for itself (ADR-0017).
				//
				// A plain List draws nothing and says nothing here. Its pool is empty only when
				// the List is, and the pinned bar is disabled then, so the user cannot reach it.
				// Nor does a Combo, which does not deal as a Deck yet — see ``dealsAsDeck``.
				guard dealsAsDeck else { return }
				result = .exhausted
				drawToken += 1
				return
			}

			result = .item(drawn)
			drawToken += 1
		}
	}

	public enum Action {
		case againButtonTapped
		/// The deck is back, so deal from it. Sent by ``reshuffleAndDeal(_:)`` once the delete
		/// has landed and the pool has been refilled — never by the view.
		case deckReshuffled
		case reshuffleButtonTapped
	}

	/// The in-flight reshuffle, so a second tap can be told there is one.
	@StoreTaskID var reshuffle

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .againButtonTapped, .deckReshuffled:
				// In place, with no memory of the last result: a plain List may deal the same Item
				// twice in a row, and nothing suppresses it. A Deck cannot repeat, because the
				// draw below is over what it has not dealt.
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
		// Three things have to hold, and one `guard` says all three: this is a List, because a
		// Combo's deal is a `ComboDraw` row and that arrives with #25; it is a Deck, because a
		// plain List has no memory to keep; and it is showing an Item, because an exhausted
		// Deck has nothing to record.
		//
		// A Combo therefore writes no `ListDraw` row, which is the rule rather than the gap:
		// drawing from a Combo leaves every member List's own deck exactly as it was
		// (ADR-0007).
		guard
			case .list(let list) = state.scope,
			list.drawMode == .deck,
			case .item(let item) = state.result
		else { return }

		@Dependency(\.date.now) var now
		@Dependency(\.defaultDatabase) var database
		let pool = state.$pool
		store.addTask {
			await withErrorReporting {
				try await database.write { db in
					try ListDraw.insert { ListDraw(itemID: item.id, createdAt: now) }.execute(db)
				}
				// The pool is a live query, and the observation that takes the dealt Item out of
				// it arrives on its own schedule. Waiting for it here is what stops the next draw
				// seeing a card that has already gone.
				try await pool.load()
			}
		}
	}

	/// Puts the whole deck back, then deals from it.
	///
	/// Not gated on exhaustion: Reshuffle is available at any time, and this is the same work
	/// whether the deck is spent or barely touched. It deals afterwards because the button
	/// sits where **Again** was, and a button in that position produces a result.
	private func reshuffleAndDeal(_ state: State) {
		// As in ``deal(_:)``: a Combo reshuffles its own `ComboDraw` rows, and those arrive
		// with #25. It never reshuffles a member List's, which is the same rule seen from the
		// other side (ADR-0007).
		guard case .list(let list) = state.scope else { return }
		// And not a second time while the first is still in flight. Each tap would otherwise
		// put the deck back and deal from it independently, so two would deal twice — the
		// second landing on a card the user never asked for, or, on a one-card deck, straight
		// back on "That's the whole deck" a moment after the card appeared.
		//
		// Deliberately untested, for the reason ``ItemEditor`` gives about its own guard: a
		// `TestStore` runs the first effect to completion before it delivers the second action,
		// so a test written against this passes with the guard removed.
		guard !reshuffle.isRunning else { return }

		@Dependency(\.defaultDatabase) var database
		// The id rather than the record: the task outlives this call, and the rest of the List
		// is not its business.
		let listID = list.id
		let pool = state.$pool
		store.addTask(id: reshuffle) {
			// `Void?` is spelled out because the closure returns nothing, and an inferred `()?`
			// is a warning.
			let reshuffled: Void? = await withErrorReporting {
				try await database.write { db in
					try ListDraw.inList(listID).delete().execute(db)
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
