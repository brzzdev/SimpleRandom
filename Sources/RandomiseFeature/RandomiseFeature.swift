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
/// This is the plain path — `drawMode == .independent`, no memory, the same Item twice in a
/// row legal and not suppressed (ADR-0004). Deck mode, the draw row and Reshuffle arrive
/// with #22, and the Combine pool with #24.
@Feature
public struct RandomiseFeature {
	public struct State {
		/// Incremented on every draw and rendered by nothing.
		///
		/// A re-roll landing on the Item already shown changes no other state, so this is the
		/// only value the sheet's haptic and its VoiceOver announcement can trigger on
		/// (ADR-0017). Not persisted — nothing about a draw is.
		///
		/// The opening draw happens in ``init(scope:)``, so the token is already `1` by the time
		/// the sheet's view exists and neither channel fires on presentation: announcing there
		/// would talk over the result the user is being shown. The contract is the *reveal*
		/// rather than the pick — in v1 they are the same instant, and anything that later
		/// separates them moves this increment rather than leaving it where the name suggests
		/// (ADR-0021).
		private(set) public var drawToken = 0

		/// Every candidate in scope, not just the winner.
		///
		/// A `@FetchAll` built from the scope, rather than a pool assembled in the reducer at
		/// draw time and discarded: this feature is a sheet child whose view can see no other
		/// state, so anything later cycling the pool has to find it here (ADR-0021).
		@FetchAll internal var pool: [Item]

		/// What the sheet is showing. `nil` only for an empty pool, which the pinned bar's
		/// disabled state means the user cannot reach.
		private(set) public var result: Item?

		public let scope: DrawScope

		/// **Again** is disabled on a one-item pool, where every draw is a repeat by definition
		/// and the haptic would be the only thing distinguishing a working button from a broken
		/// one (ADR-0017).
		public var canDrawAgain: Bool { pool.count > 1 }

		public init(scope: DrawScope) {
			self.scope = scope
			switch scope {
			case .combo:
				// #24 builds the pooled query — every Item of every member List, with membership
				// deduplicated by `listID`. Until then a Combo has no way to present this sheet,
				// and an empty pool is the safe placeholder: it disables **Again** and draws
				// nothing, rather than quietly drawing from the wrong scope.
				//
				// Reported rather than merely commented, because the failure is otherwise
				// invisible — a blank sheet with a dead button looks like an empty List.
				reportIssue("A Combo cannot be randomised yet — the pooled query arrives with #24.")
				_pool = FetchAll(Item.none)

			case .list(let listID):
				// `(createdAt, id)` ascending is the app's one sort order. Selection is uniform, so
				// the order does not change the odds — it is what makes the pool the same sequence
				// on every device, which is what a v2 animation over it would need.
				_pool = FetchAll(Item.where { $0.listID.eq(listID) }.order { ($0.createdAt, $0.id) })
			}
			// The opening result, drawn before the sheet is presented. See ``drawToken``.
			draw()
		}

		/// Picks uniformly from the pool and acknowledges it by moving ``drawToken``.
		///
		/// Uniform across the Items in scope and nothing else: `weight` is reserved and read by
		/// nothing, and adding the same text twice is the user's own weighting mechanism
		/// (ADR-0004). A one-item pool therefore always returns that Item.
		///
		/// Lives on `State` rather than in the reducer because the opening draw happens at
		/// construction and a re-roll happens on an action, and the two must be the same pick.
		/// It is still the feature's own logic rather than a client behind a seam, which is what
		/// lets a test seed the generator and assert a real draw (ADR-0011).
		internal mutating func draw() {
			@Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

			// Lifted out of the closure: `pool` is a property of an `inout self` here, and the
			// generator's closure is `@Sendable`.
			let candidates = pool
			guard let drawn = withRandomNumberGenerator({ generator in
				candidates.randomElement(using: &generator)
			}) else { return }

			result = drawn
			drawToken += 1
		}
	}

	public enum Action {
		case againButtonTapped
	}

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .againButtonTapped:
				// In place, with no memory of the last result: a plain List may deal the same Item
				// twice in a row, and nothing suppresses it.
				state.draw()
			}
		}
	}
}
