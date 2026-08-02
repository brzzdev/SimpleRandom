//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import Foundation

extension String {
	/// What goes in a `name` or a `title` column: the user's text with the whitespace they did
	/// not mean to type taken off either end.
	///
	/// It lives beside the tables rather than in one feature because it is the domain's rule —
	/// `List.name` and `Item.title` are both "trimmed, non-empty" — and both tabs' editors
	/// enforce it. Two copies of it would be two places for it to drift.
	public var trimmedForStorage: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
