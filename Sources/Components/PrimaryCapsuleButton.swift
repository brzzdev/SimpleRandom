//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SwiftUI

/// The app's primary action, wherever it appears: a full-width prominent capsule at
/// `.large`.
///
/// There is only one such action — Randomise — and this is both of its instances: pinned in
/// ``RandomiseBar``, and again in the result sheet the bar opens. Two copies of the same five
/// modifiers is what invites the second screen to honour the rule differently.
///
/// A `View` rather than a `ButtonStyle`, because a style could not hold all five:
/// `.buttonBorderShape` and `.controlSize` are environment modifiers applied outside a style,
/// `.font` and `.frame` apply to the label, and a style reaching them all would have to draw
/// its own capsule — throwing away `.borderedProminent`'s system tinting.
///
/// The label arrives already composed, as `Text`, for the reason ``IndexRow``'s caption does:
/// the words belong to whichever screen authors them (ADR-0022).
public struct PrimaryCapsuleButton: View {
	private let action: () -> Void
	private let label: Text

	public init(label: Text, action: @escaping () -> Void) {
		self.action = action
		self.label = label
	}

	public var body: some View {
		Button(action: action) {
			label
				.font(.headline)
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.borderedProminent)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
	}
}
