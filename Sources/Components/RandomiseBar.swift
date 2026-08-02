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
	public func randomiseBar(
		caption: Text,
		isEnabled: Bool,
		action: @escaping () -> Void,
	) -> some View {
		safeAreaInset(edge: .bottom) {
			RandomiseBar(caption: caption, isEnabled: isEnabled, action: action)
		}
	}
}

/// The pinned Randomise bar both detail screens render: a full-width prominent capsule with
/// a caption beneath it. Placed by ``SwiftUI/View/randomiseBar(caption:isEnabled:action:)``.
///
/// The caption arrives already composed, as `Text`, because each variant is one whole
/// catalogue entry and those entries belong to the screen that authors them — `N items` and
/// `Add an item to randomise` on the Lists path, three distinct prompts on the Combine one
/// (ADR-0022). This view owns the shape and the accessibility treatment, and no strings but
/// its own.
internal struct RandomiseBar: View {
	private let action: () -> Void
	private let caption: Text
	private let isEnabled: Bool

	internal init(caption: Text, isEnabled: Bool, action: @escaping () -> Void) {
		self.action = action
		self.caption = caption
		self.isEnabled = isEnabled
	}

	internal var body: some View {
		VStack(spacing: 8) {
			Button(action: action) {
				Text("Randomise", bundle: #bundle)
					.font(.headline)
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.disabled(!isEnabled)

			caption
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
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
}
