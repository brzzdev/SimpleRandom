//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import ComposableArchitecture2
public import SwiftUI

internal import Models

/// The result: the drawn Item alone in the middle, **Again** at the bottom, and nothing else.
///
/// No Done, no Close and no toolbar — drag is the only way out. Nothing surrounds the result
/// on the Lists path either: not the List name, not the pool size, not a counter. A counter
/// was built as a prototype and rejected as scoreboard language for something that is not a
/// game (ADR-0017); the Combine path's one secondary line arrives with #24.
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
			againButton
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

	private var againButton: some View {
		Button {
			store.send(.againButtonTapped)
		} label: {
			Text("Again", bundle: #bundle)
				.font(.headline)
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.borderedProminent)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.disabled(!store.canDrawAgain)
	}

	/// Speaks the result, because nothing in SwiftUI announces changed `Text` inside a
	/// presented sheet — so **Again** would otherwise be silent to VoiceOver rather than
	/// merely ambiguous (ADR-0017).
	///
	/// The Item's title alone on the Lists path. It posts from the view rather than as an
	/// effect from the reducer: an announcement is a UI-layer acknowledgement, and the test
	/// suite should not gain a seam that only ever tests its own mock.
	private func announce() {
		guard let title = store.result?.title else { return }
		// The user's own text, never a catalogue lookup. `.high` interrupts whatever VoiceOver
		// is saying, which is the point — the result has just changed under it.
		var announcement = AttributedString(title)
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

	/// The drawn Item, and on the Lists path the entire content of the sheet.
	private var result: some View {
		// The user's own text, so `verbatim`. It wraps to four lines and only then scales, so a
		// long title shrinks rather than truncates — and past `.accessibility3` the detent grows
		// instead, which is what keeps `minimumScaleFactor` a safety net for one absurd Item
		// rather than the thing holding the layout together (ADR-0018).
		Text(verbatim: store.result?.title ?? "")
			.font(.largeTitle)
			.bold()
			.multilineTextAlignment(.center)
			.lineLimit(4)
			.minimumScaleFactor(0.5)
	}
}
