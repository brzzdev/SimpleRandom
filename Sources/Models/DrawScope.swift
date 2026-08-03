//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

/// What a randomise is running over: one List's Items, or a Combo's pooled Items.
///
/// `RandomiseFeature` owns the draw for both surfaces, and this is the state that tells the
/// two apart — which pool to build, and which of ``ListDraw`` / ``ComboDraw`` records the
/// deal. Not a stored column: no table holds a scope.
///
/// It carries the whole record rather than its id, because the sheet needs more of it than
/// the queries do: an exhausted Deck names the List it has dealt out, and ``drawMode`` is
/// what decides whether a draw deals at all. The record is a snapshot taken when the sheet
/// opens — a rename landing behind it would go unnoticed until the sheet closes, which is a
/// second or two, and `ListDetail` holds its List the same way.
public enum DrawScope: Hashable, Sendable {
	case combo(Combo)
	case list(List)

	/// How this surface deals: `.independent` on every tap, or a Deck dealing each Item once.
	///
	/// Read from the record rather than passed alongside it, so the sheet cannot be handed a
	/// mode that disagrees with the row it is drawing from.
	public var drawMode: DrawMode {
		switch self {
		case .combo(let combo): combo.drawMode
		case .list(let list): list.drawMode
		}
	}

	/// What the user calls this — the one place the sheet says it, in an exhausted Deck's
	/// "Every item in *Name* has been dealt once."
	public var name: String {
		switch self {
		case .combo(let combo): combo.name
		case .list(let list): list.name
		}
	}
}
