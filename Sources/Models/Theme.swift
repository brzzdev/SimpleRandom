//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

/// The Light / Dark / System preference behind Settings' `Theme` row.
///
/// The one piece of state that does **not** sync: it is held in `@Shared(.appStorage)` and
/// is device-local, because a phone in a dark room and an iPad in daylight are not the same
/// question (ADR-0005). It is therefore not a table and has no reserved columns.
public enum Theme: String, CaseIterable, Hashable, Identifiable, Sendable {
	case dark
	case light
	case system

	public var id: Self { self }
}
