//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

public import SQLiteData

/// How a List or a Combo deals its Items.
///
/// `.independent` draws uniformly over everything in scope on every tap, with no memory:
/// the same Item twice in a row is legal and is not suppressed. `.deck` draws only over
/// Items with no draw row, and is **exhausted** when none are left.
///
/// The raw values are the case names, they are part of the shipped schema, and they may
/// never change: an append-only CloudKit schema cannot rename what a row already holds.
public enum DrawMode: String, CaseIterable, Hashable, QueryBindable, Sendable {
	case deck
	case independent
}
