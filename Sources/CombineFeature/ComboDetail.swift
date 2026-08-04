//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import ListDetailFeature
public import Models
public import RandomiseFeature

internal import Dependencies
internal import IssueReporting
internal import SQLiteData

/// What the pinned bar's caption says beneath the button — four sentences where the Lists tab
/// has three, because a Combo has two ways of being empty (#24, #25).
///
/// **The choice lives in state rather than in the view**, for the reason ``PoolFooter`` does:
/// the thing that picks between the sentences is then the thing a test can assert, and the
/// view renders whichever case it is handed and decides nothing.
///
/// It is also what the button's enabled state is read off — see
/// ``ComboDetail/State/canRandomise`` — so a caption explaining why the button is dimmed can
/// never be shown beside a button that is not.
public enum RandomiseCaption: Hashable, Sendable {
	/// `Deck · 10 of 13 left` — a Combo Deck's pool, running down.
	///
	/// The Combine index row's Deck caption word for word, minus the `N Lists` the row carries
	/// and this screen's title does not: opening a Combo tells you nothing different about its
	/// Deck from the row you opened it from. `0 of 13 left` is the exhausted state, where the
	/// button beside it reads **Reshuffle**.
	case deck(remaining: Int, total: Int)

	/// `The Lists in this Combo have no items` — members, but nothing in any of them.
	case noItems

	/// `Add a List to randomise` — the Combo holds no Lists at all.
	case noLists

	/// `12 items` — a plain Combo's pool.
	case pool(count: Int)
}

/// `ComboDetail` — one Combo's member Lists, the `Edit` that reopens the one form, and the
/// pinned Randomise that draws from the pooled Items of all of them (#24), running down a
/// Deck of its own as it goes (#25).
///
/// **A member row pushes the real ``ListDetail``** — the same screen the Lists tab pushes,
/// with its own pinned Randomise, its own editor sheets and its own `ListDraw` deck. Nothing
/// about it is conditional on which tab presented it, which is why that screen is a target of
/// its own rather than part of `ListsFeature` (ADR-0014). Drawing there draws from that List
/// alone and leaves this Combo's own deck untouched, and drawing here writes no `ListDraw`
/// row: "dealt in Movies" and "dealt in Friday night" are separate facts (ADR-0007).
///
/// That push is a third level of optional child state — `CombineFeature` → `ComboDetail` →
/// `ListDetail` — rather than the point at which a `[Path.State]` stack is introduced. The
/// idiom is unchanged all the way down (ADR-0013).
@Feature
public struct ComboDetail {
	/// The two sheets this screen puts over the member rows, as one optional so only one of
	/// them can be up at a time — the exclusion ``ListDetail/Destination`` states, said of this
	/// screen's pair.
	///
	/// The push is *not* one of them. A sheet and a navigation destination are not mutually
	/// exclusive presentations: pushing a member List while the form is open is a thing SwiftUI
	/// can be asked for, so `detail` is an optional of its own.
	@Feature
	public enum Destination {
		case editor(ComboEditor)
		case randomise(RandomiseFeature)
	}

	public struct State: Identifiable {
		/// The Combo this screen is about, kept live rather than snapshotted at the push.
		///
		/// `ListDetail` holds its List as a `let`, and can: a List is renamed from the index it
		/// was pushed from, so a stale copy is never what is on screen. **`Edit` is on this
		/// screen**, so a snapshot would leave the navigation title reading the old name after a
		/// rename saved, and hand ``RandomiseFeature`` a `drawMode` the user has just changed.
		@FetchOne internal var combo: Combo

		public var destination: Destination.State?

		/// The member List pushed off this screen. Its own optional rather than a third case of
		/// ``Destination``, because a push and a sheet are not mutually exclusive.
		public var detail: ListDetail.State?

		/// What this **Combo** has dealt — its own `ComboDraw` rows, never a member List's
		/// `ListDraw` rows (ADR-0007).
		///
		/// Empty for a plain Combo, which writes none — and *not* empty for a Deck switched back
		/// to plain, whose rows are preserved so that switching back resumes where it left off,
		/// exactly as `ListDetail` keeps a List's.
		///
		/// Scoped to draws of Items **still in the pool**, which is the condition
		/// `ComboSummary.index` joins on: a List dropped from the Combo takes its draws out of
		/// the arithmetic with it rather than leaving the caption reading `-2 of 5 left`.
		@FetchAll internal var draws: [ComboDraw]

		/// The member Lists and their Item counts — live, so a List renamed or filled on another
		/// device changes underneath the screen, and deduplicated by `listID`.
		@FetchAll internal var members: [ListOption]

		public var id: Combo.ID { combo.id }

		/// Whether the pinned button does anything, read off the caption rather than computed
		/// beside it: the caption is the only thing that says *why* a dimmed button is dimmed
		/// (ADR-0018), and deriving one from the other is what stops them ever disagreeing.
		///
		/// An exhausted Deck is **not** dimmed — the button reads **Reshuffle** there, and a
		/// disabled Reshuffle would be the only way out of a spent Combo Deck taken away.
		public var canRandomise: Bool {
			switch randomiseCaption {
			case .deck, .pool: true
			case .noItems, .noLists: false
			}
		}

		/// How many pooled Items this Combo has dealt.
		///
		/// Distinct by `itemID`, as `ComboSummary` counts them: `comboDraws` has no `UNIQUE`
		/// outside its primary key, so two devices dealing the same card offline leave two rows
		/// for it, and counting both would read the Deck down below zero (ADR-0008).
		internal var dealtCount: Int {
			Set(draws.map(\.itemID)).count
		}

		public var isDeck: Bool { combo.drawMode == .deck }

		/// A Combo Deck that has dealt every pooled Item it has. The pinned button reads
		/// **Reshuffle** here.
		///
		/// A Combo with nothing in it is not exhausted — it has dealt nothing because it pools
		/// nothing, and its Randomise is disabled with a prompt to add a List or some Items
		/// rather than an invitation to put back cards that were never dealt.
		public var isExhausted: Bool {
			isDeck && itemCount > 0 && remainingCount == 0
		}

		/// The Combo's pool size: every Item of every member List, summed.
		///
		/// Summed over ``members`` rather than counted by a query of its own, because those rows
		/// are already deduplicated by `listID` and an Item belongs to exactly one List — so
		/// this agrees with what ``Item/inCombo(_:)`` will pool, without a second round trip.
		/// Duplicate *Items* are not collapsed by either: two "Pizza"s are two chances
		/// (ADR-0004).
		public var itemCount: Int {
			members.reduce(0) { $0 + $1.itemCount }
		}

		/// Which sentence sits under the button. See ``RandomiseCaption``.
		///
		/// The two prompts are distinct because they ask for different things: a Combo with no
		/// Lists needs one adding here, and a Combo whose Lists are all empty needs Items adding
		/// somewhere else entirely. One prompt covering both would name neither.
		///
		/// Both prompts come before the Deck variant, exactly as `ListDetail`'s empty-List
		/// prompt does: a Deck with nothing to deal needs something adding, not putting back.
		public var randomiseCaption: RandomiseCaption {
			if members.isEmpty { return .noLists }
			if itemCount == 0 { return .noItems }
			return isDeck
				? .deck(remaining: remainingCount, total: itemCount)
				: .pool(count: itemCount)
		}

		/// How many pooled Items the Deck has left to deal. Meaningless for a plain Combo, which
		/// has no memory of what it has drawn.
		public var remainingCount: Int { itemCount - dealtCount }

		public init(combo: Combo) {
			// Seeded with the row the index already read, so the screen renders its title on the
			// first frame rather than after a query has answered.
			_combo = FetchOne(wrappedValue: combo, Combo.find(combo.id))
			// Ordered like everything else, so that a reload cannot reshuffle the rows underneath
			// an exhaustive assertion. Nothing on screen reads a draw's own order.
			_draws = FetchAll(ComboDraw.pooled(in: combo.id).order { ($0.createdAt, $0.itemID) })
			// Built here rather than declared on the property the way the index's are, for the
			// reason `ListDetail`'s items are: the query is scoped to one Combo, and the id only
			// exists once there is a Combo to read it from.
			_members = FetchAll(ListOption.inCombo(combo.id))
		}
	}

	public enum Action {
		case detail(ListDetail.Action)
		case destination(Destination.Action)
		case editButtonTapped
		case memberTapped(ListOption)
		case randomiseButtonTapped
		case reshuffleButtonTapped
	}

	public init() {}

	public var body: some Feature {
		Update { state, action in
			switch action {
			case .detail:
				break

			case .destination:
				break

			case .editButtonTapped:
				// The same form the index's leading swipe opens, reading its own membership off
				// the draft's id — there is no second home for membership, which is what lets a
				// Combo be a single Save (ADR-0020).
				state.destination = .editor(ComboEditor.State(draft: Combo.Draft(state.combo)))

			case .memberTapped(let member):
				// The real `ListDetail`, with nothing suppressed and no flag saying which tab
				// presented it. A read-only preview was the alternative and is what ADR-0014
				// rejects: it would be a second screen showing the same Items, and the pinned
				// Randomise the domain has already declared legal would be missing from it.
				state.detail = ListDetail.State(list: member.list)

			case .randomiseButtonTapped:
				// The scope is all the sheet is handed: it owns the pooled query, the pick and the
				// deal (ADR-0016). Mounted within this `send`, so the opening result is drawn
				// before SwiftUI presents anything.
				state.destination = .randomise(RandomiseFeature.State(scope: .combo(state.combo)))

			case .reshuffleButtonTapped:
				// Puts every pooled Item this Combo has dealt back — a hard delete of the whole
				// set, which is what makes it the exact inverse of the rows the draws wrote
				// (ADR-0006). Every member List's own `ListDraw` rows are left exactly where they
				// are: this Combo is putting back its own cards and nobody else's (ADR-0007).
				@Dependency(\.defaultDatabase) var database
				let comboID = state.combo.id
				store.addTask {
					await withErrorReporting {
						try await database.write { db in
							try ComboDraw.inCombo(comboID).delete().execute(db)
						}
					}
				}
			}
		}
		.ifLet(\.destination, action: \.destination) { Destination.body }
		.ifLet(\.detail, action: \.detail) { ListDetail() }
	}
}
