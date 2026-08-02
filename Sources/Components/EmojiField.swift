//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SwiftUI

internal import UIKit

/// A one-grapheme field that opens the system emoji keyboard.
///
/// SwiftUI has no API to force that keyboard, so this is a `UIViewRepresentable`. A curated
/// grid was rejected as a fixed vocabulary to maintain.
///
/// Its accessibility treatment is declared on the `UITextField` itself rather than through
/// SwiftUI modifiers, because a representable cannot apply modifiers to itself. The field
/// inherits no label, so it carries one; the emoji is what is being edited here rather than
/// an ornament, so unlike the index row's it is spoken. `None` is the empty case — an
/// unlabelled empty field would announce nothing at all and read as broken. It is one
/// element, so it is skippable in one swipe, and it gates nothing (ADR-0018).
public struct EmojiField: UIViewRepresentable {
	@Binding private var emoji: String?

	public init(emoji: Binding<String?>) {
		_emoji = emoji
	}

	public func makeCoordinator() -> Coordinator {
		Coordinator(emoji: $emoji)
	}

	public func makeUIView(context: Context) -> UITextField {
		let field = EmojiOnlyTextField()
		field.addTarget(
			context.coordinator,
			action: #selector(Coordinator.editingChanged),
			for: .editingChanged,
		)
		field.accessibilityLabel = String(localized: "Emoji", bundle: #bundle)
		// Nothing in this app clamps Dynamic Type, and a `UITextField` left alone keeps the
		// system font at a fixed size — the one place in the graph where scaling has to be
		// asked for rather than inherited (ADR-0018).
		field.adjustsFontForContentSizeCategory = true
		field.font = UIFont.preferredFont(forTextStyle: .body)
		// The field carries no visible label of its own, so the placeholder says what the row
		// is for. It is the same catalogue entry as the accessibility label.
		//
		// Alignment is left alone deliberately: `NSTextAlignment` offers `.right` but no
		// `.trailing`, and this app writes `.leading` rather than `.left` everywhere else.
		field.placeholder = String(localized: "Emoji", bundle: #bundle)
		return field
	}

	public func updateUIView(_ field: UITextField, context: Context) {
		context.coordinator.emoji = $emoji
		field.accessibilityValue = emoji ?? String(localized: "None", bundle: #bundle)
		guard field.text != emoji else { return }
		field.text = emoji
	}

	@MainActor
	public final class Coordinator: NSObject {
		fileprivate var emoji: Binding<String?>

		fileprivate init(emoji: Binding<String?>) {
			self.emoji = emoji
		}

		/// Keeps only the last grapheme typed, so the field holds one emoji however many
		/// arrive. `suffix(1)` is over `Character`s, which is what makes a flag or a skin
		/// tone survive as the one thing it looks like rather than losing its modifiers.
		@objc fileprivate func editingChanged(_ field: UITextField) {
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
