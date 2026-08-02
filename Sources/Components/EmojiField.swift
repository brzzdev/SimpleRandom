//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SwiftUI

internal import UIKit

/// A one-grapheme field that opens the system emoji keyboard.
///
/// SwiftUI has no API to force that keyboard, so the field itself is the
/// `UIViewRepresentable` below. A curated grid was rejected as a fixed vocabulary to
/// maintain.
///
/// This is a `View` wrapping the representable rather than being one, because a
/// `UIViewRepresentable` cannot apply modifiers to itself and the accessibility treatment
/// here is the whole reason the control is shared (ADR-0018): it inherits no label, so it
/// declares one, and it must stay skippable in one swipe.
public struct EmojiField: View {
	@Binding private var emoji: String?

	public init(emoji: Binding<String?>) {
		_emoji = emoji
	}

	public var body: some View {
		EmojiTextField(emoji: $emoji)
			.accessibilityLabel(Text("Emoji", bundle: #bundle))
			// The emoji is what is being edited here rather than an ornament, so unlike the
			// index row's it is spoken. `None` is the empty case: an unlabelled empty field
			// would announce nothing at all and read as broken.
			.accessibilityValue(emoji.map(Text.init(verbatim:)) ?? Text("None", bundle: #bundle))
	}
}

/// The `UITextField` seam. Two overrides do the work, and both are on the view rather than
/// the coordinator because `textInputMode` is consulted before any delegate exists.
private struct EmojiTextField: UIViewRepresentable {
	@Binding var emoji: String?

	func makeCoordinator() -> Coordinator {
		Coordinator(emoji: $emoji)
	}

	func makeUIView(context: Context) -> UITextField {
		let field = EmojiOnlyTextField()
		field.addTarget(
			context.coordinator,
			action: #selector(Coordinator.editingChanged),
			for: .editingChanged,
		)
		// The field carries no visible label of its own, so the placeholder is what says what
		// the row is for. It is the same catalogue entry as the accessibility label above.
		//
		// Alignment is left alone deliberately: `NSTextAlignment` offers `.right` but no
		// `.trailing`, and this app writes `.leading` rather than `.left` everywhere else.
		field.placeholder = String(localized: "Emoji", bundle: #bundle)
		return field
	}

	func updateUIView(_ field: UITextField, context: Context) {
		context.coordinator.emoji = $emoji
		guard field.text != emoji else { return }
		field.text = emoji
	}

	@MainActor
	final class Coordinator: NSObject {
		var emoji: Binding<String?>

		init(emoji: Binding<String?>) {
			self.emoji = emoji
		}

		/// Keeps only the last grapheme typed, so the field holds one emoji however many
		/// arrive. `suffix(1)` is over `Character`s, which is what makes a flag or a skin
		/// tone survive as the one thing it looks like rather than losing its modifiers.
		@objc func editingChanged(_ field: UITextField) {
			let last = (field.text?.suffix(1)).map(String.init)
			field.text = last
			emoji.wrappedValue = last?.isEmpty == false ? last : nil
		}
	}
}

private final class EmojiOnlyTextField: UITextField {
	/// Returning a constant identifier stops UIKit restoring whichever keyboard was last used
	/// elsewhere, which is what makes the override below stick after the first appearance.
	override var textInputContextIdentifier: String? { "" }

	/// Forcing the emoji keyboard also stops a hardware keyboard typing into the field.
	/// Accepted: the alternative is arbitrary text in a one-grapheme column.
	override var textInputMode: UITextInputMode? {
		UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
	}
}
