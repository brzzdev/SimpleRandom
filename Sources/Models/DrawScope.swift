//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

/// What a randomise is running over: one List's Items, or a Combo's pooled Items.
///
/// `RandomiseFeature` owns the draw for both surfaces, and this is the state that tells the
/// two apart — which pool to build, and which of ``ListDraw`` / ``ComboDraw`` records the
/// deal. Not a stored column: no table holds a scope.
public enum DrawScope: Hashable, Sendable {
	case combo(Combo.ID)
	case list(List.ID)
}
