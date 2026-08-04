//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SwiftUI

/// The row both indexes render: emoji · name · caption.
///
/// The caption and the accessibility label arrive already composed, as `Text`, because each
/// is one whole catalogue entry including its separator — `·` when it is read, a comma when
/// it is spoken — and those entries belong to the tab that authors them (ADR-0022). This
/// view owns the shape and the accessibility treatment, and no strings but its own.
public struct IndexRow: View {
	private let accessibilityLabel: Text
	private let caption: Text
	private let emoji: String?
	private let name: String

	public init(emoji: String?, name: String, caption: Text, accessibilityLabel: Text) {
		self.accessibilityLabel = accessibilityLabel
		self.caption = caption
		self.emoji = emoji
		self.name = name
	}

	public var body: some View {
		// Centred, not `.firstTextBaseline`: baseline alignment sits the emoji against the
		// name alone, which leaves it high by half the caption's height on every ordinary
		// row. The cost is that a name long enough to wrap under Dynamic Type centres the
		// emoji against the middle of the block rather than its first line — the rarer case,
		// traded for the misalignment that was on all of them.
		HStack(spacing: 12) {
			// A placeholder rather than nothing, so every row's name starts in the same place.
			// It renders like any other emoji: the dimming that used to mark it as a placeholder
			// read as a rendering fault against dark, and there is nothing a row gains from
			// having its own emoji told apart from the one it was given.
			Text(verbatim: emoji ?? "🎲")
				.font(.title2)

			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: name)
				caption
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			// Rows wrap and grow tall under Dynamic Type — they never clamp and never
			// truncate, which is correct for a list whose whole content is text the user
			// wrote (ADR-0018). `fixedSize` is what stops the enclosing `List` deciding
			// otherwise for a long name.
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		// One element, one label. The emoji decorates the name beside it, and the dimmed 🎲
		// placeholder would otherwise announce "game die" on every List that has not got one.
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityLabel)
	}
}
