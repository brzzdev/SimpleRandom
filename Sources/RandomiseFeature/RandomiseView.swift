//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Components
internal import Models

/// The result: the drawn Item alone in the middle, **Again** at the bottom, and nothing else.
///
/// No Done, no Close and no toolbar — drag is the only way out. Nothing surrounds the result
/// on the Lists path either: not the List name, not the pool size, not a counter. A counter
/// was built as a prototype and rejected as scoreboard language for something that is not a
/// game (ADR-0017); the Combine path's one secondary line arrives with #24.
///
/// A Deck re-rolled past its last card replaces the result with "That's the whole deck" and
/// **Again** with **Reshuffle**, in the same positions. This is the only way to that screen:
/// the detail screen's pinned button reshuffles a spent Deck rather than opening the sheet.
public struct RandomiseView: View {
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	private let store: StoreOf<RandomiseFeature>

	public init(store: StoreOf<RandomiseFeature>) {
		self.store = store
	}

	public var body: some View {
		VStack(spacing: 16) {
			Spacer(minLength: 0)
			result
			Spacer(minLength: 0)
			// One position, one button, and the two things it can be. **Reshuffle** is what an
			// exhausted Deck offers where **Again** would otherwise be — the same flag picks the
			// word and what the tap does, exactly as the pinned bar does it, so the two cannot
			// come apart.
			//
			// One button rather than a branch between two, so the control keeps its identity
			// across the swap. `_ConditionalContent` costs nothing today — v1 ships no animation
			// — but identity is what the v2 reveal would need, and ADR-0021 keeps it open.
			PrimaryCapsuleButton(
				label: isExhausted ? Text("Reshuffle", bundle: #bundle) : Text("Again", bundle: #bundle),
				action: { store.send(isExhausted ? .reshuffleButtonTapped : .againButtonTapped) },
			)
			// `canDrawAgain` alone: it is `scope.drawMode == .deck || pool.count > 1`, and an
			// exhausted deck is a deck — so **Reshuffle** is never disabled without this needing
			// to say so.
			.disabled(!store.canDrawAgain)
		}
		.padding()
		.presentationDetents([detent])
		// Both channels acknowledge one event, so both trigger on the same value — the only one
		// a re-roll landing on the Item already shown moves (ADR-0017). Neither fires on
		// presentation, because the opening draw happened before this view existed.
		//
		// Unconditional: there is no haptics toggle in Settings, and with system haptics off a
		// repeated re-roll is indistinguishable from a dead button. That gap is accepted rather
		// than papered over with a visual fallback refused on its own merits.
		.sensoryFeedback(.impact(weight: .medium), trigger: store.drawToken)
		.onChange(of: store.drawToken) {
			announce()
		}
	}

	/// A Deck that has dealt everything it has, which is the only thing that changes the
	/// button's word and its action.
	private var isExhausted: Bool { store.result == .exhausted }

	/// Speaks the result, because nothing in SwiftUI announces changed `Text` inside a
	/// presented sheet — so **Again** would otherwise be silent to VoiceOver rather than
	/// merely ambiguous (ADR-0017).
	///
	/// The Item's title alone on the Lists path. It posts from the view rather than as an
	/// effect from the reducer: an announcement is a UI-layer acknowledgement, and the test
	/// suite should not gain a seam that only ever tests its own mock.
	///
	/// An exhausted Deck announces too, and it is the one case that speaks a string of the
	/// app's rather than the user's: the result element it replaces has ceased to exist, so
	/// nothing is left for VoiceOver to re-read and focus lands wherever the system puts it.
	private func announce() {
		let spoken: AttributedString
		switch store.result {
		case .exhausted:
			spoken = AttributedString(localized: "That's the whole deck", bundle: #bundle)

		case .item(let item):
			// The user's own text, never a catalogue lookup.
			spoken = AttributedString(item.title)

		case nil:
			return
		}

		// `.high` interrupts whatever VoiceOver is saying, which is the point — the result has
		// just changed under it.
		var announcement = spoken
		announcement.accessibilitySpeechAnnouncementPriority = .high
		AccessibilityNotification.Announcement(announcement).post()
	}

	/// Fixed at `.medium`, and `.large` from the accessibility sizes up.
	///
	/// One detent rather than a range: the sheet is not resizable. The medium detent was only
	/// ever checked to `.accessibility3` — past that a long title either overflows or scales
	/// below half, and scaling down directly contradicts the setting the user just turned up
	/// (ADR-0018).
	private var detent: PresentationDetent {
		dynamicTypeSize.isAccessibilitySize ? .large : .medium
	}

	/// The drawn Item, and on the Lists path the entire content of the sheet — or, for a Deck
	/// with nothing left, what has taken its place.
	@ViewBuilder private var result: some View {
		switch store.result {
		case .exhausted:
			exhausted

		case .item(let item):
			// The user's own text, so `verbatim`. It wraps to four lines and only then scales, so
			// a long title shrinks rather than truncates — and past `.accessibility3` the detent
			// grows instead, which is what keeps `minimumScaleFactor` a safety net for one absurd
			// Item rather than the thing holding the layout together (ADR-0018).
			Text(verbatim: item.title)
				.font(.largeTitle)
				.bold()
				.multilineTextAlignment(.center)
				.lineLimit(4)
				.minimumScaleFactor(0.5)

		case nil:
			// An empty pool that is not a Deck's, which the pinned bar's disabled state means
			// the user cannot reach.
			EmptyView()
		}
	}

	/// A Deck that has dealt everything, in place of the result.
	private var exhausted: some View {
		// The name is lifted out rather than interpolated in place: a string literal inside the
		// interpolation would end the outer literal as far as the lint rule guarding
		// `bundle: #bundle` can see, and it would read the call as missing one.
		// `store.state` rather than `store.scope`, which is the store's own scoping operator.
		let name = store.state.scope.name
		return ContentUnavailableView {
			Label {
				Text("That's the whole deck", bundle: #bundle)
			} icon: {
				Image(systemName: "rectangle.stack.badge.minus")
			}
		} description: {
			Text("Every item in \(name) has been dealt once.", bundle: #bundle)
		}
	}
}
