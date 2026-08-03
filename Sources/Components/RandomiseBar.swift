//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SwiftUI

extension View {
	/// Pins the Randomise bar to the bottom of this screen.
	///
	/// The placement is part of the component rather than something each detail screen
	/// remembers: pinned chrome, not a floating button, so it never covers the last row, never
	/// dodges the keyboard, and never needs content padded around it. Both `ListDetail` and
	/// `ComboDetail` render it, and a rule written only in prose is one the second of them can
	/// honour differently.
	///
	/// `isExhausted` is what turns the button into **Reshuffle**: a spent Deck's primary action
	/// is putting the cards back, and it is offered in place of a Randomise that has nothing
	/// left to deal rather than as a second control beside it.
	///
	/// Both actions are handed over rather than one, so that the flag choosing the word also
	/// chooses what the tap does. A screen that passed a single closure would be free to leave
	/// a button reading **Reshuffle** wired to a draw, and nothing would catch it — `Components`
	/// carries views and no tests by design.
	public func randomiseBar(
		caption: Text,
		spokenCaption: Text,
		isEnabled: Bool,
		isExhausted: Bool,
		randomise: @escaping () -> Void,
		reshuffle: @escaping () -> Void,
	) -> some View {
		safeAreaInset(edge: .bottom) {
			RandomiseBar(
				caption: caption,
				spokenCaption: spokenCaption,
				isEnabled: isEnabled,
				isExhausted: isExhausted,
				randomise: randomise,
				reshuffle: reshuffle,
			)
		}
	}
}

/// The pinned Randomise bar both detail screens render: a full-width prominent capsule with
/// a caption beneath it. Placed by
/// ``SwiftUI/View/randomiseBar(caption:spokenCaption:isEnabled:isExhausted:randomise:reshuffle:)``.
///
/// The caption arrives already composed, as `Text`, because each variant is one whole
/// catalogue entry and those entries belong to the screen that authors them — `N items` and
/// `Add an item to randomise` on the Lists path, three distinct prompts on the Combine one
/// (ADR-0022). This view owns the shape and the accessibility treatment, and no strings but
/// its own.
///
/// It arrives twice, because the separator differs: `Deck · 10 of 13 left` is read and
/// `Deck, 10 of 13 left` is spoken, and each is authored rather than derived from the other.
/// Where a caption has no punctuation to differ over, both arguments are the same `Text`.
internal struct RandomiseBar: View {
	private let caption: Text
	private let isEnabled: Bool
	private let isExhausted: Bool
	private let randomise: () -> Void
	private let reshuffle: () -> Void
	private let spokenCaption: Text

	internal init(
		caption: Text,
		spokenCaption: Text,
		isEnabled: Bool,
		isExhausted: Bool,
		randomise: @escaping () -> Void,
		reshuffle: @escaping () -> Void,
	) {
		self.caption = caption
		self.isEnabled = isEnabled
		self.isExhausted = isExhausted
		self.randomise = randomise
		self.reshuffle = reshuffle
		self.spokenCaption = spokenCaption
	}

	internal var body: some View {
		VStack(spacing: 8) {
			PrimaryCapsuleButton(label: title, action: isExhausted ? reshuffle : randomise)
				.disabled(!isEnabled)

			caption
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				// The spoken form of this same caption, which differs only in its separator.
				// Overriding the child's label rather than the combined element's is what keeps
				// the button's own word — and its traits — out of a string joined in Swift.
				.accessibilityLabel(spokenCaption)
		}
		// Nothing here clamps Dynamic Type. At the largest accessibility size the bar costs
		// about a quarter of the screen permanently — capping type size on the app's primary
		// action is the least defensible place to do it, and the cost is scrolling in screens
		// that hold few rows (ADR-0018).
		.fixedSize(horizontal: false, vertical: true)
		.padding(.horizontal)
		.padding(.vertical, 12)
		.background(.bar)
		// One element, combining the button with its caption, so VoiceOver reads
		// `Randomise, Add an item to randomise, dimmed, button`. The caption is the only thing
		// that says *why* the button is dimmed, and `accessibilityHint` would put that reason
		// behind "Speak Hints" — a setting the user controls (ADR-0018).
		.accessibilityElement(children: .combine)
	}

	/// **Randomise**, or **Reshuffle** once the Deck it belongs to is spent. Both words are
	/// this component's own, so both entries live in its catalogue — and the same flag picks
	/// the word and the action above, so the two cannot come apart.
	private var title: Text {
		isExhausted
			? Text("Reshuffle", bundle: #bundle)
			: Text("Randomise", bundle: #bundle)
	}
}
